"""Lo que entra y sale de la API."""

import uuid
from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, EmailStr, Field, field_validator



class PedirCodigo(BaseModel):
    email: EmailStr


class Verificar(BaseModel):
    email: EmailStr
    codigo: str = Field(min_length=6, max_length=6)
    # Solo para quien entra por primera vez.
    nombre: str | None = Field(default=None, min_length=2, max_length=80)
    nacimiento: date | None = None
    dispositivo: str | None = Field(default=None, max_length=120)


class Refrescar(BaseModel):
    refresco: str


class Tokens(BaseModel):
    token: str
    vence_en: int
    refresco: str


class Perfil(BaseModel):
    id: uuid.UUID
    email: EmailStr
    nombre: str
    nacimiento: date | None
    creado: datetime


class CambiarPerfil(BaseModel):
    nombre: str = Field(min_length=2, max_length=80)


class ConfigRifa(BaseModel):
    desde: int = Field(ge=0)
    hasta: int = Field(ge=0)
    precio: int = Field(gt=0, description="centavos")
    asignacion: Literal["bolsa", "talonarios"] = "bolsa"
    sorteo: Literal["externo", "interno"] = "externo"
    fecha_sorteo: date | None = None
    si_no_se_vendio: Literal["resortear", "desierto", "siguiente"] = "resortear"
    premios: list[str] = Field(default_factory=lambda: ["Primer Premio"])

    @field_validator("hasta")
    @classmethod
    def _rango(cls, v: int, info):
        desde = info.data.get("desde")
        if desde is not None and v <= desde:
            raise ValueError("el número final tiene que ser mayor que el inicial")
        if desde is not None and (v - desde + 1) > 100_000:
            raise ValueError("el rango no puede superar los 100.000 números")
        return v

    @field_validator("premios")
    @classmethod
    def _validar_premios(cls, v: list[str]) -> list[str]:
        limpios = [p.strip() for p in v if p.strip()]
        if not limpios:
            return ["Primer Premio"]
        for p in limpios:
            if len(p) > 100:
                raise ValueError("la descripción del premio no puede superar los 100 caracteres")
        return limpios


class EditarPremiosEntrada(BaseModel):
    premios: list[str] = Field(min_length=1)

    @field_validator("premios")
    @classmethod
    def _validar_premios(cls, v: list[str]) -> list[str]:
        limpios = [p.strip() for p in v if p.strip()]
        if not limpios:
            raise ValueError("debe haber al menos un premio con descripción")
        for p in limpios:
            if len(p) > 100:
                raise ValueError("la descripción del premio no puede superar los 100 caracteres")
        return limpios


class NuevaCampana(BaseModel):
    id: uuid.UUID | None = None  # la genera el celular para poder crear sin señal
    tipo: Literal["rifa", "productos"]
    nombre: str = Field(min_length=3, max_length=80)
    moneda: str = Field(default="ARS", min_length=3, max_length=3)
    meta: int | None = Field(default=None, gt=0, description="centavos")
    rifa: ConfigRifa | None = None
    alias_cuenta: str | None = Field(default=None, max_length=120)


class CajaSalida(BaseModel):
    id: uuid.UUID
    tipo: str
    titular_id: uuid.UUID
    titular: str
    alias: str | None = None


class IntegranteSalida(BaseModel):
    usuario_id: uuid.UUID
    nombre: str
    rol: str
    estado: str
    cuenta_en_reparto: bool
    alta: datetime | None


class CampanaSalida(BaseModel):
    id: uuid.UUID
    tipo: str
    nombre: str
    moneda: str
    meta: int | None
    estado: str
    plan: str
    creador_id: uuid.UUID
    config: dict
    creada: datetime
    mi_rol: str
    mi_estado: str
    # Suspendida desde el panel: la app avisa y no deja cargar nada.
    suspendida: bool = False
    motivo_suspension: str | None = None


class CampanaDetalle(CampanaSalida):
    integrantes: list[IntegranteSalida]
    cajas: list[CajaSalida]


class Invitar(BaseModel):
    email: EmailStr


class CambiarEstado(BaseModel):
    estado: Literal["borrador", "activa", "cerrada", "sorteada", "liquidada", "archivada"]


class RespuestaInvitacion(BaseModel):
    respuesta: Literal["acepto", "rechazo"]


class InvitacionSalida(BaseModel):
    campana_id: uuid.UUID
    campana: str
    tipo: str
    invitado_por: str | None
    invitado: datetime
    estado: str


# --- Fase 2: Rifa, Números, Ventas y Comprobantes ---


class NumeroSalida(BaseModel):
    numero: int
    estado: str
    reserva_vence: datetime | None = None
    reserva_nota: str | None = None
    reservado_por_mi: bool = False
    vendedor_nombre: str | None = None


class ReservarNumero(BaseModel):
    nota: str | None = Field(default=None, max_length=120)


class CompradorEntrada(BaseModel):
    nombre: str = Field(min_length=2, max_length=80)
    telefono: str = Field(min_length=6, max_length=30)


class CompradorSalida(BaseModel):
    id: uuid.UUID
    nombre: str
    telefono: str | None = None


class NuevaVenta(BaseModel):
    id: uuid.UUID | None = None
    numeros: list[int] = Field(min_length=1)
    comprador: CompradorEntrada
    destino_cobro: Literal["billetera", "efectivo", "cuenta_principal", "adeudado"] = "efectivo"
    importe_cobrado: int | None = Field(default=None, ge=0)
    comprobante_id: uuid.UUID | None = None


class ProductoCrear(BaseModel):
    nombre: str = Field(min_length=1, max_length=100)
    precio: int = Field(gt=0)
    foto: str | None = None


class ProductoModificar(BaseModel):
    nombre: str | None = Field(default=None, min_length=1, max_length=100)
    precio: int | None = Field(default=None, gt=0)
    activo: bool | None = None
    foto: str | None = None


class ProductoSalida(BaseModel):
    id: uuid.UUID
    campana_id: uuid.UUID
    nombre: str
    precio: int
    foto: str | None = None
    activo: bool
    creado: datetime


class ItemVentaProductoEntrada(BaseModel):
    producto_id: uuid.UUID
    cantidad: int = Field(gt=0)


class ItemVentaProductoSalida(BaseModel):
    producto_id: uuid.UUID
    nombre: str
    cantidad: int
    precio_unitario: int
    subtotal: int


class NuevaVentaProductos(BaseModel):
    id: uuid.UUID | None = None
    items: list[ItemVentaProductoEntrada] = Field(min_length=1)
    comprador: CompradorEntrada
    destino_cobro: Literal["billetera", "efectivo", "cuenta_principal", "adeudado"] = "efectivo"
    importe_cobrado: int | None = Field(default=None, ge=0)
    entrega: Literal["pedido", "entregado"] = "pedido"
    comprobante_id: uuid.UUID | None = None


class ActualizarEntrega(BaseModel):
    entrega: Literal["pedido", "entregado"]


class VentaSalida(BaseModel):
    id: uuid.UUID
    campana_id: uuid.UUID
    vendedor_id: uuid.UUID
    vendedor_nombre: str
    comprador: CompradorSalida
    numeros: list[int] = []
    items_productos: list[ItemVentaProductoSalida] = []
    importe: int
    estado: str
    entrega: str = "pedido"
    codigo_corto: str
    creada: datetime
    total_cobrado: int
    cobro_pendiente: int
    saldo_adeudado: int


class NuevoCobro(BaseModel):
    caja_tipo: Literal["billetera", "efectivo", "cuenta_principal"]
    importe: int = Field(gt=0)
    comprobante_id: uuid.UUID | None = None


class MovimientoSalida(BaseModel):
    id: uuid.UUID
    campana_id: uuid.UUID
    tipo: str
    caja_origen: uuid.UUID | None = None
    caja_destino: uuid.UUID | None = None
    importe: int
    estado: str
    requiere_aprobacion_de: uuid.UUID | None = None
    aprobado_por: uuid.UUID | None = None
    motivo: str | None = None
    venta_id: uuid.UUID | None = None
    comprobante_id: uuid.UUID | None = None
    creado_por: uuid.UUID
    creado: datetime


class RechazarMovimiento(BaseModel):
    motivo: str = Field(min_length=3, max_length=200)


class SubirComprobante(BaseModel):
    archivo_base64: str
    mime: str = Field(default="image/jpeg", max_length=50)
    nro_operacion: str | None = Field(default=None, max_length=60)


class ComprobanteSalida(BaseModel):
    id: uuid.UUID
    sha256: str | None = None
    nro_operacion: str | None = None
    mime: str
    tamano: int
    creado: datetime
    duplicado_aviso: str | None = None


class RecaudacionCaja(BaseModel):
    caja_id: uuid.UUID
    tipo: str
    titular_id: uuid.UUID
    titular_nombre: str
    confirmado: int
    pendiente: int


class RecaudacionSalida(BaseModel):
    cobrado: int
    pendiente: int
    vendido: int
    falta_cobrar: int
    numeros_totales: int
    numeros_libres: int
    numeros_reservados: int = 0
    numeros_vendidos: int = 0
    cajas: list[RecaudacionCaja]
    productos_desglose: list[dict] = []
    gastos: int = 0


# Sincronización offline (§5)
class SyncOperacionEntrada(BaseModel):
    id: uuid.UUID
    op: str = Field(pattern="^(vender_rifa|vender_productos|actualizar_entrega)$")
    payload: dict
    creado: datetime | None = None
    creado_cliente: datetime | None = None


class SyncPushEntrada(BaseModel):
    operaciones: list[SyncOperacionEntrada]


class SyncOperacionResultado(BaseModel):
    id: uuid.UUID
    estado: str  # 'ok', 'conflicto', 'rechazado'
    motivo: str | None = None
    detalle: dict | None = None
    secuencia: int | None = None
    resultado: dict | None = None


class SyncPushSalida(BaseModel):
    resultados: list[SyncOperacionResultado]


class SyncPullSalida(BaseModel):
    cursor: int
    hay_mas: bool = False
    cambios: list[dict] = []
    snapshot: dict | None = None


# Liquidación y Cierre (§3.9)
class ParticipanteLiquidacion(BaseModel):
    usuario_id: uuid.UUID
    nombre: str
    en_mano: int
    gastos_bolsillo: int = 0
    parte: int
    saldo: int  # > 0 debe pagar, < 0 debe recibir


class TransferenciaSugerida(BaseModel):
    id: uuid.UUID | None = None
    de_usuario_id: uuid.UUID
    de_nombre: str
    a_usuario_id: uuid.UUID
    a_nombre: str
    importe: int
    estado: str = "pendiente"  # pendiente, pagada, confirmada
    comprobante_id: uuid.UUID | None = None
    actualizada: datetime | None = None


TransferenciaLiquidacionSalida = TransferenciaSugerida


class OpcionLiquidacion(BaseModel):
    base: str
    recaudado: int
    gastos: int
    neto: int
    parte: int
    participantes: list[ParticipanteLiquidacion]
    transferencias: list[TransferenciaSugerida]


class SimulacionLiquidacionSalida(BaseModel):
    puede_liquidar: bool
    impedimentos: list[str]
    cobrada: OpcionLiquidacion
    vendida: OpcionLiquidacion


class ConfirmarLiquidacionEntrada(BaseModel):
    base: str = Field(pattern="^(cobrada|vendida)$")


class LiquidacionSalida(BaseModel):
    campana_id: uuid.UUID
    base: str
    neto: int
    parte: int
    recaudado: int
    gastos: int
    detalle: dict
    confirmada_por: uuid.UUID
    confirmada_por_nombre: str | None = None
    creada: datetime
    transferencias: list[TransferenciaSugerida]


class ActualizarTransferenciaEntrada(BaseModel):
    accion: str = Field(pattern="^(pagar|confirmar)$")
    comprobante_id: uuid.UUID | None = None


# Gastos (§3.7)
class CrearGastoEntrada(BaseModel):
    descripcion: str = Field(min_length=2, max_length=500)
    importe: int = Field(gt=0)
    origen: str = Field(pattern="^(bolsillo|caja)$")
    caja_id: uuid.UUID | None = None
    comprobante_id: uuid.UUID | None = None


class GastoSalida(BaseModel):
    id: uuid.UUID
    campana_id: uuid.UUID
    movimiento_id: uuid.UUID
    descripcion: str
    importe: int
    origen: str
    caja_id: uuid.UUID | None = None
    caja_nombre: str | None = None
    estado: str
    creado_por: uuid.UUID
    creado_por_nombre: str
    aprobado_por: uuid.UUID | None = None
    aprobado_por_nombre: str | None = None
    motivo_rechazo: str | None = None
    comprobante_id: uuid.UUID | None = None
    creado: datetime


# Entregas entre cajas (§3.6)
class CrearEntregaEntrada(BaseModel):
    caja_origen_id: uuid.UUID
    caja_destino_id: uuid.UUID
    importe: int = Field(gt=0)
    comprobante_id: uuid.UUID | None = None


# Anulaciones (§3.8)
class SolicitarAnulacionEntrada(BaseModel):
    motivo: str = Field(min_length=3, max_length=500)


# Sorteos de rifa (§3.3 y §7.8)
class PremioSorteoEntrada(BaseModel):
    orden: int = Field(default=1, ge=1)
    numero_sorteado: int = Field(ge=0)
    premio: str | None = Field(default=None, max_length=100)


class RegistrarSorteoEntrada(BaseModel):
    items: list[PremioSorteoEntrada] | None = None
    # Retrocompatibilidad para premio único
    numero_sorteado: int | None = Field(default=None, ge=0)
    premio: str | None = Field(default=None, max_length=100)
    regla_no_vendido: str | None = None


class SorteoSalida(BaseModel):
    model_config = {"from_attributes": True}

    campana_id: uuid.UUID
    orden: int = 1
    numero_sorteado: int
    numero_ganador: int | None = None
    premio: str | None = None
    estado_resultado: str
    ganador_nombre: str | None = None
    ganador_telefono: str | None = None
    vendedor_id: uuid.UUID | None = None
    vendedor_nombre: str | None = None
    venta_id: uuid.UUID | None = None
    codigo_corto: str | None = None
    creado_por: uuid.UUID
    creado: datetime


# Avisos (§7.9 de DEFINICION.md)
class NuevoAvisoEntrada(BaseModel):
    mensaje: str = Field(min_length=1, max_length=2000)
    fijado: bool = False


class AvisoSalida(BaseModel):
    model_config = {"from_attributes": True}

    id: uuid.UUID
    campana_id: uuid.UUID
    autor_id: uuid.UUID
    autor_nombre: str | None = None
    mensaje: str
    fijado: bool
    creado: datetime


# Ranking (§7.7 de DEFINICION.md)
class ItemRankingSalida(BaseModel):
    posicion: int
    vendedor_id: uuid.UUID
    nombre: str
    cantidad: int
    total_vendido: int
    total_cobrado: int
    porcentaje: float


class RankingSalida(BaseModel):
    campana_id: uuid.UUID
    tipo: str
    items: list[ItemRankingSalida]


# Dispositivos y Push FCM (§5.7 de DEFINICION.md)
class RegistroDispositivoEntrada(BaseModel):
    fcm_token: str = Field(min_length=10, max_length=255)
    plataforma: str = Field(default="android", max_length=20)
    version_app: str | None = Field(default=None, max_length=20)


class DispositivoSalida(BaseModel):
    model_config = {"from_attributes": True}

    id: uuid.UUID
    usuario_id: uuid.UUID
    fcm_token: str
    plataforma: str
    version_app: str | None = None
    actualizado: datetime


# --- Planes y mejoras con MercadoPago (§11) ---


class PlanSalida(BaseModel):
    codigo: str
    nombre: str
    orden: int
    precio: int
    limite_integrantes: int | None
    limite_numeros: int | None
    limite_ventas: int | None
    limite_campanas_activas: int | None
    publicidad: bool


class UsoPlan(BaseModel):
    integrantes: int
    numeros: int | None       # tamaño del talonario (sólo rifas)
    ventas: int | None        # ventas confirmadas (sólo productos)


class MejoraPosible(BaseModel):
    plan: PlanSalida
    a_pagar: int              # centavos: la diferencia con el plan actual


class EstadoPlanCampana(BaseModel):
    actual: PlanSalida
    uso: UsoPlan
    mejoras: list[MejoraPosible]
    puede_pagar: bool         # el servidor tiene MercadoPago configurado
    compra_pendiente: uuid.UUID | None


class PedirMejora(BaseModel):
    plan: str = Field(min_length=1, max_length=20)


class MejoraCreada(BaseModel):
    compra_id: uuid.UUID
    url_pago: str
    importe: int
    prueba: bool


class CompraSalida(BaseModel):
    id: uuid.UUID
    plan_desde: str
    plan_hasta: str
    importe: int
    estado: str
    detalle_estado: str | None
    creada: datetime
    acreditada: datetime | None


class RedactarRecordatorio(BaseModel):
    """Tono con el que la IA local redacta el recordatorio de deuda."""

    tono: Literal["amable", "firme"] = "amable"
