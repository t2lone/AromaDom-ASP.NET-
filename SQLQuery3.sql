
USE AromaDom;
GO
-- 1. Список материалов с требуемым количеством (то, что показывает главная)
SELECT
    material_id,
    name,
    material_type_name AS category,
    unit_short_name     AS unit,
    price,
    stock_quantity,
    min_quantity,
    required_quantity
FROM dbo.v_material_card
ORDER BY name;
GO
-- 2. То же требуемое количество, но без представления — видно саму формулу:
--    сумма норм расхода по всем рецептурам материала
SELECT
    m.material_id,
    m.name,
    SUM(mp.quantity) AS required_quantity
FROM dbo.material AS m
JOIN dbo.material_product AS mp ON mp.material_id = m.material_id
GROUP BY m.material_id, m.name
ORDER BY m.name;
GO
-- 3. Поиск по наименованию или типу материала
DECLARE @search NVARCHAR(120) = N'масло';
SELECT name, material_type_name, unit_short_name, price, required_quantity
FROM dbo.v_material_card
WHERE name LIKE N'%' + @search + N'%'
   OR material_type_name LIKE N'%' + @search + N'%'
ORDER BY name;
GO
-- 4. Фильтр по категории (типу материала)
DECLARE @typeId INT = 3;   -- 3 = «Ароматическое масло»
SELECT name, material_type_name, unit_short_name, stock_quantity, required_quantity
FROM dbo.v_material_card
WHERE material_type_id = @typeId
ORDER BY name;
GO
-- 5. Категории и количество позиций в каждой
SELECT
    mt.material_type_id,
    mt.name AS category,
    COUNT(m.material_id) AS materials_count
FROM dbo.material_type AS mt
LEFT JOIN dbo.material AS m ON m.material_type_id = mt.material_type_id
GROUP BY mt.material_type_id, mt.name
ORDER BY mt.name;
GO
-- 6. Продукция, в рецептуре которой используется материал, и итог по материалу
DECLARE @materialId INT = 1;   -- 1 = «Соевый воск премиум»
SELECT product_name, article, product_type_name, quantity
FROM dbo.v_material_product
WHERE material_id = @materialId
ORDER BY product_name;
SELECT SUM(quantity) AS required_quantity
FROM dbo.material_product
WHERE material_id = @materialId;
GO
-- 7. Материалы, остаток которых ниже минимального (пора закупать)
SELECT name, material_type_name, stock_quantity, min_quantity, unit_short_name
FROM dbo.v_material_card
WHERE is_below_min = 1
ORDER BY name;
GO
-- 8. Справочники
SELECT material_type_id, name, loss_percent FROM dbo.material_type ORDER BY name;
SELECT unit_id, name, short_name FROM dbo.unit ORDER BY unit_id;
SELECT product_type_id, name, coefficient FROM dbo.product_type ORDER BY name;
GO
-- 9. Данные для метода расчёта продукции (коэффициент типа и потери сырья)
SELECT
    pt.name  AS product_type,
    pt.coefficient,
    mt.name  AS material_type,
    mt.loss_percent
FROM dbo.product_type AS pt
CROSS JOIN dbo.material_type AS mt
WHERE pt.product_type_id = 1
  AND mt.material_type_id = 1;
GO
-- 10. Пример добавления материала.
--     Транзакция откатывается, чтобы не оставлять тестовую запись.
BEGIN TRANSACTION;
INSERT INTO dbo.material
    (material_type_id, unit_id, name, price, package_quantity, stock_quantity, min_quantity)
VALUES
    (1, 1, N'Тестовый воск', 100.00, 10, 5, 2);
DECLARE @newMaterialId INT = SCOPE_IDENTITY();
SELECT @newMaterialId AS new_material_id;
SELECT material_id, name, price, stock_quantity FROM dbo.material WHERE material_id = @newMaterialId;
ROLLBACK TRANSACTION;
GO
-- 11. Пример изменения остатка: триггер пишет историю, транзакция откатывается
BEGIN TRANSACTION;
DECLARE @editMaterialId INT = 1;
UPDATE dbo.material
   SET stock_quantity = stock_quantity - 5
 WHERE material_id = @editMaterialId;
SELECT old_quantity, new_quantity, changed_at, note
FROM dbo.material_stock_history
WHERE material_id = @editMaterialId
ORDER BY history_id DESC;
ROLLBACK TRANSACTION;
GO
-- 12. Контроль наполнения и целостности
SELECT N'Типы материалов' AS entity, COUNT(*) AS rows_count FROM dbo.material_type
UNION ALL SELECT N'Единицы измерения', COUNT(*) FROM dbo.unit
UNION ALL SELECT N'Материалы', COUNT(*) FROM dbo.material
UNION ALL SELECT N'Типы продукции', COUNT(*) FROM dbo.product_type
UNION ALL SELECT N'Продукция', COUNT(*) FROM dbo.product
UNION ALL SELECT N'Рецептуры', COUNT(*) FROM dbo.material_product;
GO
DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS;
GO