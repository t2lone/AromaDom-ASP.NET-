-- =============================================================================
--  «Арома Дом» — полный скрипт базы данных AromaDom
--  Создаёт базу, 7 таблиц в 3НФ, представления, триггеры и загружает данные
--  заказчика (18 материалов, 14 продуктов, 73 рецептуры).
--  Выполнить в SQL Server Management Studio или:
--    sqlcmd -S "(localdb)\MSSQLLocalDB" -E -i db\AromaDom.sql
-- =============================================================================

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

USE AromaDom;
GO
SET NOCOUNT ON;
GO

-- Типы материалов -----------------------------------------------------------
SET IDENTITY_INSERT dbo.material_type ON;
INSERT INTO dbo.material_type (material_type_id, name, loss_percent) VALUES
    (1, N'Соевый воск', 0.12),
    (2, N'Пчелиный воск', 0.18),
    (3, N'Ароматическое масло', 0.25),
    (4, N'Краситель', 0.08),
    (5, N'Фитиль', 0.03),
    (6, N'Стеклянная тара', 0.04),
    (7, N'Керамическая тара', 0.06),
    (8, N'Декор', 0.1),
    (9, N'Упаковка', 0.05),
    (10, N'Этикетка', 0.02);
SET IDENTITY_INSERT dbo.material_type OFF;
GO

-- Единицы измерения ---------------------------------------------------------
SET IDENTITY_INSERT dbo.unit ON;
INSERT INTO dbo.unit (unit_id, name, short_name) VALUES
    (1, N'килограмм', N'кг'),
    (2, N'литр', N'л'),
    (3, N'штука', N'шт'),
    (4, N'метр', N'м');
SET IDENTITY_INSERT dbo.unit OFF;
GO

-- Типы продукции ------------------------------------------------------------
SET IDENTITY_INSERT dbo.product_type ON;
INSERT INTO dbo.product_type (product_type_id, name, coefficient) VALUES
    (1, N'Классическая свеча', 1),
    (2, N'Премиальная свеча', 1.15),
    (3, N'Подарочный набор', 1.3),
    (4, N'Интерьерная свеча', 1.2),
    (5, N'Мини-свеча', 0.8),
    (6, N'Сезонная коллекция', 1.25);
SET IDENTITY_INSERT dbo.product_type OFF;
GO

-- Материалы -----------------------------------------------------------------
SET IDENTITY_INSERT dbo.material ON;
INSERT INTO dbo.material (material_id, material_type_id, unit_id, name, price, package_quantity, stock_quantity, min_quantity) VALUES
    (1, 1, 1, N'Соевый воск премиум', 890, 20, 120, 40),
    (2, 1, 1, N'Соевый воск EcoBlend', 760, 25, 95, 30),
    (3, 2, 1, N'Пчелиный воск натуральный', 1450, 10, 48, 15),
    (4, 3, 2, N'Масло лаванды', 3200, 1, 18.5, 6),
    (5, 3, 2, N'Масло ванили', 2950, 1, 22, 8),
    (6, 3, 2, N'Масло цитрусовое', 2870, 1, 16.7, 5),
    (7, 4, 1, N'Краситель янтарный', 640, 0.5, 6.2, 2),
    (8, 4, 1, N'Краситель розовый', 615, 0.5, 5.1, 1.5),
    (9, 5, 3, N'Фитиль хлопковый 8 см', 4.5, 500, 2500, 800),
    (10, 5, 3, N'Фитиль хлопковый 12 см', 5.8, 400, 1800, 600),
    (11, 6, 3, N'Стакан прозрачный 200 мл', 28, 100, 950, 300),
    (12, 6, 3, N'Стакан матовый 250 мл', 34, 60, 620, 200),
    (13, 7, 3, N'Чаша керамическая белая', 72, 40, 280, 80),
    (14, 8, 1, N'Сухоцветы лаванды', 520, 0.3, 4.8, 1.5),
    (15, 9, 4, N'Лента сатиновая бежевая', 12, 50, 340, 120),
    (16, 9, 3, N'Коробка подарочная малая', 18, 50, 420, 150),
    (17, 10, 3, N'Этикетка фирменная круглая', 3.2, 250, 1800, 500),
    (18, 10, 3, N'Наклейка предупреждающая', 2.1, 200, 1600, 400);
SET IDENTITY_INSERT dbo.material OFF;
GO

-- Продукция -----------------------------------------------------------------
SET IDENTITY_INSERT dbo.product ON;
INSERT INTO dbo.product (product_id, product_type_id, article, name, min_price) VALUES
    (1, 1, N'AR-001', N'Свеча «Лавандовый вечер»', 980),
    (2, 1, N'AR-002', N'Свеча «Ванильный крем»', 950),
    (3, 1, N'AR-003', N'Свеча «Цитрусовый сад»', 970),
    (4, 2, N'AR-004', N'Свеча «Белый мускус»', 1290),
    (5, 2, N'AR-005', N'Свеча «Дикая орхидея»', 1360),
    (6, 4, N'AR-006', N'Свеча «Теплый янтарь»', 1490),
    (7, 4, N'AR-007', N'Свеча «Сандаловое дерево»', 1520),
    (8, 5, N'AR-008', N'Мини-свеча «Лаванда»', 420),
    (9, 5, N'AR-009', N'Мини-свеча «Ваниль»', 410),
    (10, 5, N'AR-010', N'Мини-свеча «Цитрус»', 430),
    (11, 3, N'AR-011', N'Набор «Уютный дом»', 2190),
    (12, 3, N'AR-012', N'Набор «Теплый вечер»', 2340),
    (13, 6, N'AR-013', N'Свеча «Зимние специи»', 1380),
    (14, 6, N'AR-014', N'Свеча «Хвойный лес»', 1410);
SET IDENTITY_INSERT dbo.product OFF;
GO

-- Рецептуры -----------------------------------------------------------------
INSERT INTO dbo.material_product (material_id, product_id, quantity) VALUES
    (1, 1, 0.18),
    (4, 1, 0.009),
    (9, 1, 1),
    (11, 1, 1),
    (17, 1, 1),
    (1, 2, 0.18),
    (5, 2, 0.01),
    (9, 2, 1),
    (11, 2, 1),
    (17, 2, 1),
    (2, 3, 0.175),
    (6, 3, 0.011),
    (9, 3, 1),
    (11, 3, 1),
    (17, 3, 1),
    (1, 4, 0.22),
    (5, 4, 0.006),
    (10, 4, 1),
    (12, 4, 1),
    (17, 4, 1),
    (1, 5, 0.225),
    (4, 5, 0.004),
    (10, 5, 1),
    (12, 5, 1),
    (17, 5, 1),
    (3, 6, 0.28),
    (7, 6, 0.004),
    (10, 6, 1),
    (13, 6, 1),
    (17, 6, 1),
    (3, 7, 0.285),
    (5, 7, 0.003),
    (10, 7, 1),
    (13, 7, 1),
    (17, 7, 1),
    (2, 8, 0.07),
    (4, 8, 0.003),
    (9, 8, 1),
    (11, 8, 1),
    (2, 9, 0.07),
    (5, 9, 0.003),
    (9, 9, 1),
    (11, 9, 1),
    (2, 10, 0.07),
    (6, 10, 0.003),
    (9, 10, 1),
    (11, 10, 1),
    (1, 11, 0.18),
    (4, 11, 0.009),
    (9, 11, 1),
    (11, 11, 1),
    (15, 11, 1.2),
    (16, 11, 1),
    (17, 11, 1),
    (1, 12, 0.225),
    (5, 12, 0.01),
    (10, 12, 1),
    (12, 12, 1),
    (15, 12, 1.5),
    (16, 12, 1),
    (17, 12, 1),
    (1, 13, 0.21),
    (5, 13, 0.008),
    (7, 13, 0.003),
    (10, 13, 1),
    (12, 13, 1),
    (18, 13, 1),
    (1, 14, 0.215),
    (6, 14, 0.004),
    (7, 14, 0.002),
    (10, 14, 1),
    (12, 14, 1),
    (18, 14, 1);
GO

-- Контроль наполнения -------------------------------------------------------
SELECT N'Типы материалов' AS entity, COUNT(*) AS rows_count FROM dbo.material_type
UNION ALL SELECT N'Единицы измерения', COUNT(*) FROM dbo.unit
UNION ALL SELECT N'Материалы', COUNT(*) FROM dbo.material
UNION ALL SELECT N'Типы продукции', COUNT(*) FROM dbo.product_type
UNION ALL SELECT N'Продукция', COUNT(*) FROM dbo.product
UNION ALL SELECT N'Рецептуры', COUNT(*) FROM dbo.material_product;
GO
