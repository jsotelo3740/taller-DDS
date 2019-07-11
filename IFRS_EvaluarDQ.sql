IF OBJECT_ID('IFRS_EvaluarDQ') IS NOT NULL
BEGIN
    DROP PROCEDURE dbo.IFRS_EvaluarDQ 
    IF OBJECT_ID('IFRS_EvaluarDQ') IS NOT NULL
        PRINT '<<< FAILED DROPPING PROCEDURE IFRS_EvaluarDQ  >>>'
    ELSE
        PRINT '<<< DROPPED PROCEDURE IFRS_EvaluarDQ  >>>'
END
go
-----------------------------------------------------------------------------------------------------
CREATE PROCEDURE IFRS_EvaluarDQ
    @Pfecha  DATETIME 
AS
/* -------------------------------------------------------------------------------------------------
NOMBRE  :   IFRS_EvaluarDQ 

FUNCION :   EVALUAR LAS REGLAS DQ SOBRE LOS RESULTADOS DE LOS PROCESOS IFRS.

HISTORIA:
	 JSO @11-DIC-2018 * Pet. 68913/68914: IFRS9  - Creacion.  
&& JSO @10-JUL-2019 * Pet. 71266: IFRS9 .   
------------------------------------------------------------------------------------------------- */

-- DECLARO CURSOR
DECLARE CReglasDQ CURSOR FOR
    SELECT DQ.ID_DQ, TAB.TABLA, DQ.CONDICION, DQ.ID_TABLA 
	FROM IFRS_DQ DQ, IFRS_TablaDQ TAB
    WHERE DQ.ID_TABLA=TAB.ID_TABLA
    AND DQ.HABILITADA = 'S'
    ORDER BY DQ.ID_DQ ASC
FOR READ ONLY

--DECLARO VARIABLES
DECLARE
@VIdDQ               VARCHAR(15),
@VQuery          	   VARCHAR(1000),
@VTabla               VARCHAR(30),
@VCant                INT,
@VCantTotKO       INT,
@VObs                 VARCHAR(255),
@VProcId             INT,
@VQuery              VARCHAR(1500),
@VIdTabla            INT

IF (@Pfecha IS NULL)         --Si no se ingresa una fecha por parametro se toma la del dia de la fecha
    SELECT @Pfecha = GETDATE()
    
SELECT @VObs = CONVERT (CHAR(10), @Pfecha, 103) + " IFRS_EvaluarDQ"

-- GRABO COMIENZO EN LA TABLA PROCESOS
EXEC GrabarProcS 1400, @VProcId OUT , @VObs

-- INICIALIZAR CONTADOR
SELECT  @VCantTotKO = 0


-- COMIENZAR RECORRIDO DE REGLAS
OPEN CReglasDQ
WHILE 1 = 1
    BEGIN
        FETCH CReglasDQ INTO @VIdDQ, @VTabla, @VQuery, @VIdTabla
        IF @@SQLSTATUS != 0 BREAK       -- Si no hay más registros sale 
        
        EXEC (@VQuery) 	-- Ejecutamos la query
        
        -- SI EXISTE UN ERROR CON LA REGLA
        IF @@error <> 0
            BEGIN
                SELECT 'Error regla: ' + @VIdDQ + 
                       ' - Tabla: ' +  @VTabla + 
                       ' - Condicion: ' + @VCondicion +
                       ' - Query: ' + @VQuery

                SELECT ''
                 
            END

        -- QUE NO HAYA NULOS
        SELECT  @VCant      = ISNULL(@VCant,0),
                @VIdDQ      = ISNULL(@VIdDQ,' '),
                @VTabla     = ISNULL(@VTabla,' '),
                @VCondicion = ISNULL(@VCondicion,' '),
                @VIdTabla   = ISNULL(@VIdTabla,0)

        -- REGISTRO EL RESULTADO DE EVALUAR LA REGLA
        IF (@VCant = 0) --NO EXISTEN RECHAZADOS POR LA REGLA
            
            BEGIN
                INSERT IFRS_EjecucionDQ (ID_DQ, PROCID, RESULTADO, ID_TABLA, TABLA, QUERY, CANT_KO)
                VALUES (@VIdDQ, @VProcId, 'OK', @VIdTabla, @VTabla, @VQuery, 0)  
            END

        ELSE    -- EXISTEN RECHAZADOS POR LA REGLA
            
            BEGIN
                INSERT IFRS_EjecucionDQ (ID_DQ, PROCID, RESULTADO, ID_TABLA, TABLA, QUERY, CANT_KO)
                VALUES (@VIdDQ, @VProcId, 'KO', @VIdTabla, @VTabla, @VQuery, @VCant) 
            END
        
        -- CUENTA EL TOTAL DE REGISTROS QUE NO CUMPLE CON LAS REGLAS
            SELECT @VCantTotKO = @VCantTotKO + @VCant           

        CONTINUE        
    
    END

-- CIERRE DE CURSOR    
CLOSE CReglasDQ
DEALLOCATE CURSOR CReglasDQ                            

-- GENERAR INFORME DE ERRORES
IF (@VCantTotKO > 0) -- GENERO INFORME DE REGLAS KO SOLO SI EXISTEN CASOS
    BEGIN
        
        CREATE TABLE #Salida
            (
                Linea CHAR(1408)
            )
    -- CABECERA --
		INSERT INTO #Salida
		SELECT 'FECHA DE EJECUCION:' + CONVERT(CHAR(17), FHEjec, 21)
		FROM Procesos
		WHERE ProcId = @VProcId

		INSERT INTO #Salida
		SELECT ''


        INSERT INTO #Salida
        SELECT  'COD_DQ' + ';' +
                'TABLA' + ';' +
                'CAMPO' + ';' +
                'DESCRIPCION' + ';' +
                'CANT_KO' + ';' +
                'QUERY' 
    	
    -- CUERPO --
        INSERT INTO #Salida    
        SELECT  
                EJDQ.ID_DQ + ';' + 
                EJDQ.TABLA + ';' +
                DQ.CAMPO + ';' +
                DQ.DESCRIPCION + ';' +
                CONVERT(VARCHAR, EJDQ.CANT_KO) + ';' +
                EJDQ.QUERY
        FROM    IFRS_EjecucionDQ EJDQ, 
                Procesos Pro, 
                IFRS_DQ DQ
        WHERE EJDQ.PROCID = Pro.ProcId
            AND EJDQ.ID_TABLA = DQ.ID_TABLA
            AND EJDQ.ID_DQ = DQ.ID_DQ
            AND EJDQ.PROCID = @VProcId
            AND EJDQ.RESULTADO = 'KO'

        SELECT 
                substring(Linea,1,255),
                substring(Linea,256,255),
                substring(Linea,511,255), 
                substring(Linea,766,255),
                substring(Linea,1021,255),
                substring(Linea,1276,255)
        FROM #Salida
                    
    END  -- FIN DEL INFORME DE REGLAS KO 


/* --------------------------- */
/* GRABAR EL FINAL DEL PROCESO */
/* --------------------------- */

SELECT
    @VObs = ' | QUE NO CUMPLEN LAS REGLAS DQ: ' + CONVERT (VARCHAR, @VCantTotKO)

UPDATE Procesos 
    SET FHFinal = GETDATE(),
    Observaciones = Observaciones + @VObs
WHERE ProcId = @VProcId
-----------------------------------------------------------------------------------------------------
GO

IF OBJECT_ID('dbo.IFRS_EvaluarDQ') IS NOT NULL
    PRINT '<<< CREATED PROCEDURE dbo.IFRS_EvaluarDQ >>>'
ELSE
    PRINT '<<< FAILED CREATING PROCEDURE dbo.IFRS_EvaluarDQ >>>'
go
IF (@@servername = 'DSDESA08')
    IF (db_name() = 'PSA_Credit')
        GRANT EXECUTE ON IFRS_EvaluarDQ to psadesa
    ELSE
        GRANT EXECUTE ON IFRS_EvaluarDQ to credpru
ELSE
    GRANT EXECUTE ON IFRS_EvaluarDQ to credprod
go
