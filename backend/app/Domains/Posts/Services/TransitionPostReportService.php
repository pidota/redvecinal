<?php

namespace App\Domains\Posts\Services;

use App\Domains\Posts\Enums\PostReportStatus;
use App\Domains\Posts\Exceptions\PostDomainException;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostReport;
use App\Domains\Posts\Support\PostModerationEventRecorder;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Gate;

/**
 * Transiciones administrativas de un reporte.
 *
 * Convención de campos (sin migración en 5D.2):
 * - reviewing: resolved_by es el funcionario que toma el caso; resolved_at y
 *   resolution_note quedan nulos.
 * - resolved / dismissed: resolved_by, resolved_at y resolution_note registran
 *   el cierre. Esos estados son terminales.
 *
 * Auditoría (5D.5): si el reporte tiene post_id, se registra un evento
 * report_reviewing|report_resolved|report_dismissed en post_moderation_events
 * dentro de la misma transacción. Sin post_id no hay fila de auditoría
 * (la columna post_id de esa tabla no es nullable); el estado queda en
 * post_reports. No se inventa un post_id.
 */
class TransitionPostReportService
{
    public const RESOLUTION_NOTE_MAX_LENGTH = 2000;

    public const EVENT_REVIEWING = 'report_reviewing';

    public const EVENT_RESOLVED = 'report_resolved';

    public const EVENT_DISMISSED = 'report_dismissed';

    /**
     * @var array<string, list<string>>
     */
    private const ALLOWED_TRANSITIONS = [
        'open' => ['reviewing', 'resolved', 'dismissed'],
        'reviewing' => ['resolved', 'dismissed'],
        'resolved' => [],
        'dismissed' => [],
    ];

    public function __construct(private readonly PostModerationEventRecorder $recorder) {}

    public function execute(
        PostReport $report,
        User $actor,
        PostReportStatus $targetStatus,
        ?string $resolutionNote = null,
    ): PostReport {
        return DB::transaction(function () use ($report, $actor, $targetStatus, $resolutionNote) {
            $locked = PostReport::query()->whereKey($report->id)->lockForUpdate()->firstOrFail();

            Gate::forUser($actor)->authorize('resolve', $locked);

            $from = $locked->status;
            if (! $this->isAllowedTransition($from, $targetStatus)) {
                throw new PostDomainException('Transición de reporte no permitida.');
            }

            $normalizedNote = $this->normalizeResolutionNote($targetStatus, $resolutionNote);

            if ($targetStatus === PostReportStatus::Reviewing) {
                $locked->update([
                    'status' => PostReportStatus::Reviewing,
                    'resolved_by' => $actor->id,
                    'resolved_at' => null,
                    'resolution_note' => null,
                ]);
            } else {
                $locked->update([
                    'status' => $targetStatus,
                    'resolved_by' => $actor->id,
                    'resolved_at' => now(),
                    'resolution_note' => $normalizedNote,
                ]);
            }

            $this->recordTransitionAudit($locked, $actor, $from, $targetStatus);

            return $locked->fresh();
        });
    }

    public function isAllowedTransition(PostReportStatus $from, PostReportStatus $to): bool
    {
        return in_array($to->value, self::ALLOWED_TRANSITIONS[$from->value] ?? [], true);
    }

    private function normalizeResolutionNote(PostReportStatus $targetStatus, ?string $resolutionNote): ?string
    {
        if ($targetStatus === PostReportStatus::Reviewing) {
            return null;
        }

        if (! is_string($resolutionNote)) {
            throw new PostDomainException('El fundamento de resolución es obligatorio.');
        }

        $normalized = trim($resolutionNote);

        if ($normalized === '') {
            throw new PostDomainException('El fundamento de resolución es obligatorio.');
        }

        if (mb_strlen($normalized) > self::RESOLUTION_NOTE_MAX_LENGTH) {
            throw new PostDomainException(
                'El fundamento de resolución no puede superar '.self::RESOLUTION_NOTE_MAX_LENGTH.' caracteres.'
            );
        }

        return $normalized;
    }

    private function recordTransitionAudit(
        PostReport $report,
        User $actor,
        PostReportStatus $from,
        PostReportStatus $to,
    ): void {
        if ($report->post_id === null) {
            return;
        }

        $post = Post::query()->withTrashed()->find($report->post_id);
        if (! $post instanceof Post) {
            return;
        }

        $this->recorder->record(
            $post,
            $this->auditEventName($to),
            $actor,
            $from->value,
            $to->value,
            ['report_id' => $report->id],
        );
    }

    private function auditEventName(PostReportStatus $status): string
    {
        return match ($status) {
            PostReportStatus::Reviewing => self::EVENT_REVIEWING,
            PostReportStatus::Resolved => self::EVENT_RESOLVED,
            PostReportStatus::Dismissed => self::EVENT_DISMISSED,
            PostReportStatus::Open => throw new PostDomainException('Evento de auditoría de reporte no soportado.'),
        };
    }
}
