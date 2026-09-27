"""Configuración de la API. Todo viene del entorno o de archivos de secretos."""

import functools
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


def _leer(ruta: str | None) -> str:
    if not ruta:
        raise RuntimeError("falta la ruta del archivo de secreto")
    return Path(ruta).read_text(encoding="utf-8").strip()


def _pares(texto: str) -> dict[str, str]:
    """Lee líneas CLAVE=valor, ignorando vacías y comentarios."""
    datos: dict[str, str] = {}
    for linea in texto.splitlines():
        linea = linea.strip()
        if not linea or linea.startswith("#") or "=" not in linea:
            continue
        nombre, valor = linea.split("=", 1)
        datos[nombre.strip()] = valor.strip()
    return datos


class Ajustes(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="MITI_", extra="ignore")

    entorno: str = "desarrollo"

    db_host: str = "db"
    db_puerto: int = 5432
    db_nombre: str = "miti"
    db_usuario: str = "miti"
    db_clave_archivo: str | None = None
    db_clave: str | None = None

    # Archivo con líneas CLAVE=valor: CLAVE_MAESTRA y CLAVE_JWT (base64).
    claves_archivo: str | None = None
    # Archivo con la configuración del SMTP de sole.ar (SMTP_HOST, SMTP_USUARIO, ...).
    smtp_archivo: str | None = None

    minutos_token: int = 15
    dias_refresco: int = 60
    minutos_codigo: int = 10
    intentos_codigo: int = 5
    codigos_por_hora: int = 5
    # Direcciones de prueba: se registran pero no se mandan (evita rebotes).
    dominios_sin_envio: str = "pruebas.miti.sole.ar"
    edad_minima: int = 13
    carpeta_archivos: str = "/srv/miti/data/archivos"
    # Credenciales de Firebase para las notificaciones push. Si el archivo no
    # está, el envío queda en modo registro y la app no se cae.
    firebase_credenciales: str = "/run/secrets/firebase"
    # Archivo con MP_ACCESS_TOKEN y MP_WEBHOOK_SECRET de MercadoPago (§11).
    mercadopago_archivo: str | None = None
    # Dirección pública del servidor: la usan el webhook y las páginas de vuelta.
    url_publica: str = "https://miti.sole.ar"
    # IA local (Ollama en el mismo VPS). Escucha sólo en la red interna de Docker.
    ollama_url: str = "http://172.28.0.1:11434"
    modelo_ia: str = "llama3.2:3b"

    @property
    def url_db(self) -> str:
        clave = self.db_clave or _leer(self.db_clave_archivo)
        return (
            f"postgresql+asyncpg://{self.db_usuario}:{clave}"
            f"@{self.db_host}:{self.db_puerto}/{self.db_nombre}"
        )

    @functools.cached_property
    def claves(self) -> dict[str, str]:
        datos = _pares(_leer(self.claves_archivo))
        for obligatoria in ("CLAVE_MAESTRA", "CLAVE_JWT"):
            if obligatoria not in datos:
                raise RuntimeError(f"falta {obligatoria} en el archivo de claves")
        return datos

    @property
    def mercadopago(self) -> dict[str, str]:
        """Credenciales de MercadoPago; vacío si todavía no se cargaron.

        Se lee en cada uso (no se guarda en memoria) para que cambiar el token
        de prueba por el de producción no requiera reiniciar nada más que el archivo.
        """
        if not self.mercadopago_archivo or not Path(self.mercadopago_archivo).exists():
            return {}
        return _pares(Path(self.mercadopago_archivo).read_text(encoding="utf-8"))

    @property
    def es_produccion(self) -> bool:
        return self.entorno == "produccion"


@functools.lru_cache
def ajustes() -> Ajustes:
    return Ajustes()
