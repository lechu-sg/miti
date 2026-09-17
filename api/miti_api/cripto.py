"""Cifrado de campos sensibles y huellas para poder buscarlos.

- `cifrar` / `descifrar`: AES-256-GCM con la clave maestra, que vive fuera de la base.
- `huella`: HMAC-SHA256 con una clave derivada de la maestra. Permite buscar por
  igualdad exacta (un email) sin guardar el dato en claro ni poder deshacerlo.
"""

import base64
import hashlib
import hmac
import os

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from .config import ajustes

_VERSION = b"\x01"


def _clave_maestra() -> bytes:
    clave = base64.b64decode(ajustes().claves["CLAVE_MAESTRA"])
    if len(clave) != 32:
        raise RuntimeError("CLAVE_MAESTRA debe tener 32 bytes en base64")
    return clave


def _clave_huella() -> bytes:
    return hashlib.blake2b(_clave_maestra(), digest_size=32, person=b"miti-huella").digest()


def cifrar(texto: str | None) -> bytes | None:
    if texto is None:
        return None
    nonce = os.urandom(12)
    datos = AESGCM(_clave_maestra()).encrypt(nonce, texto.encode("utf-8"), _VERSION)
    return _VERSION + nonce + datos


def descifrar(dato: bytes | None) -> str | None:
    if dato is None:
        return None
    version, nonce, cuerpo = dato[:1], dato[1:13], dato[13:]
    if version != _VERSION:
        raise ValueError("versión de cifrado desconocida")
    return AESGCM(_clave_maestra()).decrypt(nonce, cuerpo, version).decode("utf-8")


def huella(texto: str) -> bytes:
    return hmac.new(_clave_huella(), texto.encode("utf-8"), hashlib.sha256).digest()


def hash_simple(texto: str) -> bytes:
    """Para códigos de un solo uso y tokens de refresco (no son secretos de largo plazo)."""
    return hashlib.sha256(texto.encode("utf-8")).digest()


def normalizar_email(email: str) -> str:
    return email.strip().lower()
