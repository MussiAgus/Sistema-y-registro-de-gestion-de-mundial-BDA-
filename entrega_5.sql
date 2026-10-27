

-- PARTE 1: DDL (CREACIÓN DE BASE DE DATOS Y TABLAS CORREGIDAS)

USE master;
GO
IF DB_ID('Mundial2026') IS NOT NULL
BEGIN
    ALTER DATABASE Mundial2026 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE Mundial2026;
END
GO
CREATE DATABASE Mundial2026;
GO
USE Mundial2026;
GO

CREATE SCHEMA cfg; 
GO
CREATE SCHEMA op;  
GO

-- 1. Países, Sedes y Partidos
CREATE TABLE op.Pais (
    IdPais INT IDENTITY(1,1) PRIMARY KEY,
    Nombre VARCHAR(100) NOT NULL,
    HorarioUTC VARCHAR(10) NULL
);

CREATE TABLE op.Sede (
    IdSede INT IDENTITY(1,1) PRIMARY KEY,
    NombreEstadio VARCHAR(100) NOT NULL,
    Ciudad VARCHAR(100) NOT NULL,
    UsoHorario VARCHAR(10) NOT NULL,
    Capacidad INT NOT NULL
);

CREATE TABLE op.Partido (
    IdPartido INT IDENTITY(1,1) PRIMARY KEY,
    Fecha DATE NOT NULL,
    Hora TIME NOT NULL,
    Fase VARCHAR(50) NOT NULL,
    PublicoAsistente INT NULL,
    Resultado VARCHAR(20) NULL
);

CREATE TABLE op.Club (
    IdClub INT IDENTITY(1,1) PRIMARY KEY,
    Nombre VARCHAR(100) NOT NULL
);

-- 2. Selecciones, Planteles y Jugadores
CREATE TABLE op.Seleccion (
    IdSeleccion INT IDENTITY(1,1) PRIMARY KEY,
    IdPais INT NOT NULL FOREIGN KEY REFERENCES op.Pais(IdPais)
);

CREATE TABLE op.Plantel (
    IdPlantel INT IDENTITY(1,1) PRIMARY KEY,
    IdSeleccion INT NOT NULL FOREIGN KEY REFERENCES op.Seleccion(IdSeleccion)
);

CREATE TABLE op.Jugador (
    IdJugador INT IDENTITY(1,1) PRIMARY KEY,
    IdPlantel INT NOT NULL FOREIGN KEY REFERENCES op.Plantel(IdPlantel),
    Nombre VARCHAR(100) NOT NULL,
    Apellido VARCHAR(100) NOT NULL,
    Nacionalidad VARCHAR(50) NOT NULL

);

-- 3. Alineación
CREATE TABLE op.Alineacion (
    IdAlineacion INT IDENTITY(1,1) PRIMARY KEY,
    IdPartido INT NOT NULL FOREIGN KEY REFERENCES op.Partido(IdPartido),
    IdPlantel INT NOT NULL FOREIGN KEY REFERENCES op.Plantel(IdPlantel),
    EsquemaTactico VARCHAR(20) NULL

);

-- Intermedia para el rombo "compone una" que tiene el atributo Posición
CREATE TABLE op.Alineacion_Jugador (
    IdAlineacion INT NOT NULL FOREIGN KEY REFERENCES op.Alineacion(IdAlineacion),
    IdJugador INT NOT NULL FOREIGN KEY REFERENCES op.Jugador(IdJugador),
    Posicion VARCHAR(50) NOT NULL,
    PRIMARY KEY (IdAlineacion, IdJugador)
);

-- 4. Tarjetas y Reglas
CREATE TABLE cfg.Regla_Suspencion (
    IdRegla INT IDENTITY(1,1) PRIMARY KEY,
    Canti_requerida INT NOT NULL,
    Partidos_suspension INT NOT NULL,
    Fase_Limpieza VARCHAR(50) NULL

);

CREATE TABLE cfg.Tipo_Tarjeta (
    IdTipoTarjeta INT PRIMARY KEY,
    IdRegla INT NULL FOREIGN KEY REFERENCES cfg.Regla_Suspencion(IdRegla), 
    Descripcion VARCHAR(50) NOT NULL
);

CREATE TABLE op.Tarjeta (
    IdTarjeta INT IDENTITY(1,1) PRIMARY KEY,
    IdPartido INT NOT NULL FOREIGN KEY REFERENCES op.Partido(IdPartido), 
    IdJugador INT NOT NULL FOREIGN KEY REFERENCES op.Jugador(IdJugador), 
    IdTipoTarjeta INT NOT NULL FOREIGN KEY REFERENCES cfg.Tipo_Tarjeta(IdTipoTarjeta),
    Minuto INT NOT NULL,
    Motivo VARCHAR(255) NOT NULL

);


GO


-- PARTE 2: PROCEDIMIENTO ALMACENADO (ABM JUGADOR ADAPTADO)

CREATE OR ALTER PROCEDURE op.usp_AltaJugador
    @IdPlantel INT,
    @Nombre VARCHAR(100),
    @Apellido VARCHAR(100),
    @Nacionalidad VARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @MensajeErrores NVARCHAR(MAX) = '';

    -- Validaciones agrupadas
    IF NOT EXISTS (SELECT 1 FROM op.Plantel WHERE IdPlantel = @IdPlantel) SET @MensajeErrores += 'El plantel especificado no existe. | ';
    IF @Nombre IS NULL OR LTRIM(RTRIM(@Nombre)) = '' SET @MensajeErrores += 'El nombre no puede estar vacío. | ';
    IF @Apellido IS NULL OR LTRIM(RTRIM(@Apellido)) = '' SET @MensajeErrores += 'El apellido no puede estar vacío. | ';
    IF @Nacionalidad IS NULL OR LTRIM(RTRIM(@Nacionalidad)) = '' SET @MensajeErrores += 'La nacionalidad es obligatoria. | ';

    IF LEN(@MensajeErrores) > 0
    BEGIN
        DECLARE @ErrorThrow NVARCHAR(2048) = 'VALIDACIONES FALLIDAS: ' + @MensajeErrores;
        THROW 50001, @ErrorThrow, 1;
    END

    INSERT INTO op.Jugador (IdPlantel, Nombre, Apellido, Nacionalidad)
    VALUES (@IdPlantel, @Nombre, @Apellido, @Nacionalidad);
END;
GO


-- PARTE 3: LÓGICA DE NEGOCIO (TARJETAS Y CURSORES ADAPTADOS)

CREATE OR ALTER PROCEDURE op.usp_RegistrarTarjeta_Y_CalcularSuspension
    @IdPartido INT,
    @IdJugador INT,
    @IdTipoTarjeta INT,
    @Minuto INT,
    @Motivo VARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @MensajeErrores NVARCHAR(MAX) = '';

    -- Validaciones
    IF NOT EXISTS (SELECT 1 FROM op.Partido WHERE IdPartido = @IdPartido) SET @MensajeErrores += 'El partido no existe. | ';
    IF NOT EXISTS (SELECT 1 FROM op.Jugador WHERE IdJugador = @IdJugador) SET @MensajeErrores += 'El jugador no existe. | ';
    IF NOT EXISTS (SELECT 1 FROM cfg.Tipo_Tarjeta WHERE IdTipoTarjeta = @IdTipoTarjeta) SET @MensajeErrores += 'El tipo de tarjeta no existe. | ';
    IF @Minuto < 0 OR @Minuto > 130 SET @MensajeErrores += 'El minuto debe estar entre 0 y 130. | ';
    IF @Motivo IS NULL OR LEN(LTRIM(RTRIM(@Motivo))) < 5 SET @MensajeErrores += 'El motivo debe tener al menos 5 caracteres. | ';

    IF LEN(@MensajeErrores) > 0
    BEGIN
        DECLARE @ErrorThrow NVARCHAR(2048) = 'VALIDACIONES FALLIDAS: ' + @MensajeErrores;
        THROW 50003, @ErrorThrow, 1;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

 
        INSERT INTO op.Tarjeta (IdPartido, IdJugador, IdTipoTarjeta, Minuto, Motivo)
        VALUES (@IdPartido, @IdJugador, @IdTipoTarjeta, @Minuto, @Motivo);

        DECLARE @TarjetasAcumuladas INT = 0;
        DECLARE @ReglaRequerida INT = 0;
        DECLARE @PartidosDeSancion INT = 0;

        SELECT @ReglaRequerida = rs.Canti_requerida, @PartidosDeSancion = rs.Partidos_suspension
        FROM cfg.Tipo_Tarjeta tt
        INNER JOIN cfg.Regla_Suspencion rs ON tt.IdRegla = rs.IdRegla
        WHERE tt.IdTipoTarjeta = @IdTipoTarjeta;

        DECLARE cursor_tarjetas CURSOR FOR
            SELECT IdTarjeta 
            FROM op.Tarjeta 
            WHERE IdJugador = @IdJugador AND IdTipoTarjeta = @IdTipoTarjeta;

        DECLARE @IdTarjetaRecorrida INT;
        OPEN cursor_tarjetas;
        FETCH NEXT FROM cursor_tarjetas INTO @IdTarjetaRecorrida;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @TarjetasAcumuladas = @TarjetasAcumuladas + 1;
            FETCH NEXT FROM cursor_tarjetas INTO @IdTarjetaRecorrida;
        END

        CLOSE cursor_tarjetas;
        DEALLOCATE cursor_tarjetas;

        IF @ReglaRequerida > 0 AND @TarjetasAcumuladas >= @ReglaRequerida
        BEGIN
            PRINT '>>> ATENCIÓN: El Jugador ID ' + CAST(@IdJugador AS VARCHAR) + 
                  ' alcanzó el límite de tarjetas y debe ser SUSPENDIDO por ' + 
                  CAST(@PartidosDeSancion AS VARCHAR) + ' partido(s). <<<';
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO


-- PARTE 4: TESTING (Adaptado a las nuevas relaciones)

PRINT '================ INICIANDO TESTING ================';

-- Poblado de Tablas Paramétricas
INSERT INTO cfg.Regla_Suspencion (Canti_requerida, Partidos_suspension, Fase_Limpieza) VALUES (2, 1, 'Semifinal');
INSERT INTO cfg.Tipo_Tarjeta (IdTipoTarjeta, IdRegla, Descripcion) VALUES (1, 1, 'Amarilla');

-- Poblado de Datos Base
INSERT INTO op.Pais (Nombre, HorarioUTC) VALUES ('Argentina', 'UTC-3');
INSERT INTO op.Seleccion (IdPais) VALUES (1); 
INSERT INTO op.Plantel (IdSeleccion) VALUES (1);

-- TEST 1: ABM Jugador exitoso
EXEC op.usp_AltaJugador @IdPlantel = 1, @Nombre = 'Lionel', @Apellido = 'Messi', @Nacionalidad = 'Argentina';

-- Poblado de Partido
INSERT INTO op.Partido (Fecha, Hora, Fase) VALUES ('2026-06-15', '16:00:00', 'Grupos');

PRINT '--- TEST 2: Messi recibe primera amarilla en el Partido 1 ---';
EXEC op.usp_RegistrarTarjeta_Y_CalcularSuspension @IdPartido = 1, @IdJugador = 1, @IdTipoTarjeta = 1, @Minuto = 45, @Motivo = 'Falta';

PRINT '--- TEST 3: Messi recibe segunda amarilla en el mismo partido (Debe imprimir mensaje de suspensión por consola) ---';
EXEC op.usp_RegistrarTarjeta_Y_CalcularSuspension @IdPartido = 1, @IdJugador = 1, @IdTipoTarjeta = 1, @Minuto = 88, @Motivo = 'Protesta';

PRINT '--- EVIDENCIA: TARJETAS REGISTRADAS ---';
SELECT * FROM op.Tarjeta;
GO