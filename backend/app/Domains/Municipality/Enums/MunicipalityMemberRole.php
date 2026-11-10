<?php

namespace App\Domains\Municipality\Enums;

enum MunicipalityMemberRole: string
{
    case Administrador = 'administrador';
    case Funcionario = 'funcionario';
}
