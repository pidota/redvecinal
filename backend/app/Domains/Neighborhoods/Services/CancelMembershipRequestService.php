<?php

namespace App\Domains\Neighborhoods\Services;

use App\Domains\Neighborhoods\Enums\MembershipRequestStatus;
use App\Domains\Neighborhoods\Exceptions\MembershipRequestException;
use App\Domains\Neighborhoods\Models\NeighborhoodMembershipRequest;
use App\Models\User;
use Illuminate\Support\Facades\DB;

class CancelMembershipRequestService
{
    public function execute(NeighborhoodMembershipRequest $request, User $user): NeighborhoodMembershipRequest
    {
        if ($request->user_id !== $user->id) {
            throw new MembershipRequestException('No puedes cancelar esta solicitud.', 403);
        }

        return DB::transaction(function () use ($request) {
            $locked = NeighborhoodMembershipRequest::query()
                ->whereKey($request->id)
                ->lockForUpdate()
                ->firstOrFail();

            if ($locked->status !== MembershipRequestStatus::Pending) {
                throw new MembershipRequestException('Solo se pueden cancelar solicitudes pendientes.', 409);
            }

            $locked->update([
                'status' => MembershipRequestStatus::Cancelled,
                'cancelled_at' => now(),
            ]);

            return $locked->fresh();
        });
    }
}
