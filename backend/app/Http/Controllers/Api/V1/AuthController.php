<?php

namespace App\Http\Controllers\Api\V1;

use App\Domains\Auth\Services\MobileApiAccessService;
use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\Auth\LoginRequest;
use App\Http\Resources\Api\V1\MobileUserResource;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\PersonalAccessToken;

class AuthController extends Controller
{
    public function __construct(
        private readonly MobileApiAccessService $mobileAccess,
    ) {}

    public function login(LoginRequest $request): JsonResponse
    {
        $email = $request->normalizedEmail();

        /** @var User|null $user */
        $user = User::query()->whereRaw('LOWER(email) = ?', [$email])->first();

        if ($user === null || ! Hash::check($request->validated('password'), $user->password)) {
            return response()->json([
                'message' => 'Las credenciales proporcionadas no son correctas.',
            ], 401);
        }

        if (! $this->mobileAccess->mayObtainMobileToken($user)) {
            return response()->json([
                'message' => 'Las credenciales proporcionadas no son correctas.',
            ], 401);
        }

        $expirationDays = config('red_vecinal.mobile_auth.token_expiration_days');
        $expiresAt = is_int($expirationDays) && $expirationDays > 0
            ? now()->addDays($expirationDays)
            : null;

        $token = $user->createToken(
            $request->validated('device_name'),
            ['*'],
            $expiresAt,
        );

        return response()->json([
            'token' => $token->plainTextToken,
            'token_type' => 'Bearer',
            'user' => new MobileUserResource($user),
        ]);
    }

    public function logout(Request $request): Response
    {
        $accessToken = $request->user()?->currentAccessToken();

        if ($accessToken instanceof PersonalAccessToken) {
            $accessToken->delete();
        }

        return response()->noContent();
    }

    public function me(Request $request): JsonResponse
    {
        return response()->json(
            (new MobileUserResource($request->user()))->resolve()
        );
    }
}
