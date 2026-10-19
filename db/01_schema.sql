-- =============================================================================
--  «Арома Дом» — подсистема учёта материалов
--  СУБД: Microsoft SQL Server (LocalDB), база AromaDom
--  Схема: 7 таблиц, третья нормальная форма, ссылочная целостность
--
--  Соглашение об именовании:
--    таблицы и поля — snake_case, единственное число;
--    PK — <сущность>_id, FK — совпадает по имени с PK родителя;
--    ограничения — ck_/uq_/fk_/df_, индексы — ix_, представления — v_.
--
--  Скрипт идемпотентен: удаляет прежние объекты и создаёт схему заново.
-- =============================================================================

USE master;
GO
IF DB_ID(N'AromaDom') IS NULL
    CREATE DATABASE AromaDom;
GO
USE AromaDom;
GO

-- Удаление в порядке зависимостей -------------------------------------------
IF OBJECT_ID(N'dbo.v_material_product', N'V') IS NOT NULL DROP VIEW dbo.v_material_product;
IF OBJECT_ID(N'dbo.v_material_card', N'V') IS NOT NULL DROP VIEW dbo.v_material_card;
IF OBJECT_ID(N'dbo.trg_material_stock_history', N'TR') IS NOT NULL DROP TRIGGER dbo.trg_material_stock_history;
IF OBJECT_ID(N'dbo.trg_material_updated_at', N'TR') IS NOT NULL DROP TRIGGER dbo.trg_material_updated_at;
IF OBJECT_ID(N'dbo.material_stock_history', N'U') IS NOT NULL DROP TABLE dbo.material_stock_history;
IF OBJECT_ID(N'dbo.material_product', N'U') IS NOT NULL DROP TABLE dbo.material_product;
IF OBJECT_ID(N'dbo.product', N'U') IS NOT NULL DROP TABLE dbo.product;
IF OBJECT_ID(N'dbo.material', N'U') IS NOT NULL DROP TABLE dbo.material;
IF OBJECT_ID(N'dbo.unit', N'U') IS NOT NULL DROP TABLE dbo.unit;
IF OBJECT_ID(N'dbo.product_type', N'U') IS NOT NULL DROP TABLE dbo.product_type;
IF OBJECT_ID(N'dbo.material_type', N'U') IS NOT NULL DROP TABLE dbo.material_type;
GO

-- Справочник типов материалов -------------------------------------------------
CREATE TABLE dbo.material_type (
    material_type_id INT           IDENTITY(1,1) NOT NULL,
    name             NVARCHAR(100) NOT NULL,
    loss_percent     DECIMAL(5,2)  NOT NULL CONSTRAINT df_material_type_loss DEFAULT (0),
    CONSTRAINT pk_material_type PRIMARY KEY (material_type_id),
    CONSTRAINT uq_material_type_name UNIQUE (name),
    CONSTRAINT ck_material_type_loss CHECK (loss_percent >= 0 AND loss_percent < 100)
);
GO

-- Справочник единиц измерения ------------------------------------------------
CREATE TABLE dbo.unit (
    unit_id    INT          IDENTITY(1,1) NOT NULL,
    name       NVARCHAR(50) NOT NULL,
    short_name NVARCHAR(10) NOT NULL,
    CONSTRAINT pk_unit PRIMARY KEY (unit_id),
    CONSTRAINT uq_unit_name UNIQUE (name),
    CONSTRAINT uq_unit_short_name UNIQUE (short_name)
);
GO

-- Справочник типов продукции -------------------------------------------------
CREATE TABLE dbo.product_type (
    product_type_id INT           IDENTITY(1,1) NOT NULL,
    name            NVARCHAR(100) NOT NULL,
    coefficient     DECIMAL(9,4)  NOT NULL,
    CONSTRAINT pk_product_type PRIMARY KEY (product_type_id),
    CONSTRAINT uq_product_type_name UNIQUE (name),
    CONSTRAINT ck_product_type_coef CHECK (coefficient > 0)
);
GO

-- Материал -------------------------------------------------------------------
CREATE TABLE dbo.material (
    material_id      INT           IDENTITY(1,1) NOT NULL,
    material_type_id INT           NOT NULL,
    unit_id          INT           NOT NULL,
    name             NVARCHAR(120) NOT NULL,
    price            DECIMAL(18,2) NOT NULL,
    package_quantity DECIMAL(18,3) NOT NULL CONSTRAINT df_material_pack DEFAULT (1),
    stock_quantity   DECIMAL(18,3) NOT NULL CONSTRAINT df_material_stock DEFAULT (0),
    min_quantity     DECIMAL(18,3) NOT NULL CONSTRAINT df_material_min DEFAULT (0),
    description      NVARCHAR(500) NULL,
    image_path       NVARCHAR(255) NULL,
    created_at       DATETIME2(0)  NOT NULL CONSTRAINT df_material_created DEFAULT (SYSDATETIME()),
    updated_at       DATETIME2(0)  NOT NULL CONSTRAINT df_material_updated DEFAULT (SYSDATETIME()),
    CONSTRAINT pk_material PRIMARY KEY (material_id),
    CONSTRAINT uq_material_name UNIQUE (name),
    CONSTRAINT ck_material_price CHECK (price >= 0),
    CONSTRAINT ck_material_pack CHECK (package_quantity > 0),
    CONSTRAINT ck_material_stock CHECK (stock_quantity >= 0),
    CONSTRAINT ck_material_min CHECK (min_quantity >= 0),
    CONSTRAINT fk_material_type FOREIGN KEY (material_type_id)
        REFERENCES dbo.material_type (material_type_id),
    CONSTRAINT fk_material_unit FOREIGN KEY (unit_id)
        REFERENCES dbo.unit (unit_id)
);
GO

CREATE INDEX ix_material_type ON dbo.material (material_type_id);
CREATE INDEX ix_material_unit ON dbo.material (unit_id);
GO

-- Продукция ------------------------------------------------------------------
CREATE TABLE dbo.product (
    product_id      INT           IDENTITY(1,1) NOT NULL,
    product_type_id INT           NOT NULL,
    article         NVARCHAR(30)  NOT NULL,
    name            NVARCHAR(150) NOT NULL,
    min_price       DECIMAL(18,2) NOT NULL CONSTRAINT df_product_price DEFAULT (0),
    description     NVARCHAR(500) NULL,
    image_path      NVARCHAR(255) NULL,
    created_at      DATETIME2(0)  NOT NULL CONSTRAINT df_product_created DEFAULT (SYSDATETIME()),
    updated_at      DATETIME2(0)  NOT NULL CONSTRAINT df_product_updated DEFAULT (SYSDATETIME()),
    CONSTRAINT pk_product PRIMARY KEY (product_id),
    CONSTRAINT uq_product_article UNIQUE (article),
    CONSTRAINT uq_product_name UNIQUE (name),
    CONSTRAINT ck_product_price CHECK (min_price >= 0),
    CONSTRAINT fk_product_type FOREIGN KEY (product_type_id)
        REFERENCES dbo.product_type (product_type_id)
);
GO

CREATE INDEX ix_product_type ON dbo.product (product_type_id);
GO

-- Рецептура: норма расхода материала на единицу продукции ---------------------
CREATE TABLE dbo.material_product (
    material_id INT           NOT NULL,
    product_id  INT           NOT NULL,
    quantity    DECIMAL(18,4) NOT NULL,
    CONSTRAINT pk_material_product PRIMARY KEY (material_id, product_id),
    CONSTRAINT ck_material_product_qty CHECK (quantity > 0),
    CONSTRAINT fk_mp_material FOREIGN KEY (material_id)
        REFERENCES dbo.material (material_id) ON DELETE CASCADE,
    CONSTRAINT fk_mp_product FOREIGN KEY (product_id)
        REFERENCES dbo.product (product_id) ON DELETE CASCADE
);
GO

CREATE INDEX ix_material_product_product ON dbo.material_product (product_id);
GO

-- История изменения остатков --------------------------------------------------
CREATE TABLE dbo.material_stock_history (
    history_id   BIGINT        IDENTITY(1,1) NOT NULL,
    material_id  INT           NOT NULL,
    old_quantity DECIMAL(18,3) NOT NULL,
    new_quantity DECIMAL(18,3) NOT NULL,
    changed_at   DATETIME2(0)  NOT NULL CONSTRAINT df_history_changed DEFAULT (SYSDATETIME()),
    note         NVARCHAR(200) NULL,
    CONSTRAINT pk_material_stock_history PRIMARY KEY (history_id),
    CONSTRAINT fk_history_material FOREIGN KEY (material_id)
        REFERENCES dbo.material (material_id) ON DELETE CASCADE
);
GO

CREATE INDEX ix_history_material ON dbo.material_stock_history (material_id, changed_at);
GO

-- Представление «карточка материала» с требуемым количеством ------------------
CREATE VIEW dbo.v_material_card AS
SELECT
    m.material_id,
    m.name,
    m.material_type_id,
    mt.name       AS material_type_name,
    mt.loss_percent,
    m.unit_id,
    u.short_name  AS unit_short_name,
    m.price,
    m.package_quantity,
    m.stock_quantity,
    m.min_quantity,
    COALESCE((
        SELECT SUM(mp.quantity)
        FROM dbo.material_product AS mp
        WHERE mp.material_id = m.material_id
    ), 0) AS required_quantity,
    CAST(CASE WHEN m.stock_quantity < m.min_quantity THEN 1 ELSE 0 END AS BIT) AS is_below_min
FROM dbo.material AS m
JOIN dbo.material_type AS mt ON mt.material_type_id = m.material_type_id
JOIN dbo.unit AS u ON u.unit_id = m.unit_id;
GO

-- Представление «продукция по материалу» --------------------------------------
CREATE VIEW dbo.v_material_product AS
SELECT
    mp.material_id,
    p.product_id,
    p.article,
    p.name AS product_name,
    pt.name AS product_type_name,
    mp.quantity
FROM dbo.material_product AS mp
JOIN dbo.product AS p ON p.product_id = mp.product_id
JOIN dbo.product_type AS pt ON pt.product_type_id = p.product_type_id;
GO

-- Отметка времени изменения материала -----------------------------------------
CREATE TRIGGER dbo.trg_material_updated_at
ON dbo.material
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE m
       SET updated_at = SYSDATETIME()
      FROM dbo.material AS m
      JOIN inserted AS i ON i.material_id = m.material_id;
END;
GO

-- Журнал изменений остатка ----------------------------------------------------
CREATE TRIGGER dbo.trg_material_stock_history
ON dbo.material
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.material_stock_history (material_id, old_quantity, new_quantity, note)
    SELECT i.material_id, d.stock_quantity, i.stock_quantity, N'Изменение остатка при редактировании материала'
      FROM inserted AS i
      JOIN deleted  AS d ON d.material_id = i.material_id
     WHERE i.stock_quantity <> d.stock_quantity;
END;
GO

PRINT N'Схема AromaDom создана: 7 таблиц, 2 представления, 2 триггера.';
GO
