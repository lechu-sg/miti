# Pruebas de extremo a extremo

Corren contra el servidor de prueba, no contra una base local. Necesitan la clave SSH
del VPS, porque el código de acceso todavía no se manda por email: se lee del registro.

```bash
python api/pruebas/prueba_fase1.py
```

Cada corrida crea cuentas nuevas (`ana.<marca>@pruebas.miti.sole.ar`), así que se puede
repetir todas las veces que haga falta. Los datos quedan en la base de prueba.
