"""Генерация скрипта наполнения БД AromaDom из файлов заказчика.

Читает пять книг Excel с пометкой import, нормализует значения
(проценты текстом «0,12%», запятая как разделитель) и пишет
db/02_seed.sql с явными идентификаторами.

Запуск:  python tools/generate_seed_sql.py
"""

from __future__ import annotations

import re
from decimal import Decimal, InvalidOperation
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "db" / "source"
OUTPUT = ROOT / "db" / "02_seed.sql"

UNIT_NAMES = {
    "кг": ("килограмм", "кг"),
    "л": ("литр", "л"),
    "м": ("метр", "м"),
    "шт": ("штука", "шт"),
}


def text(value: object) -> str:
    """Нормализует строку: неразрывные пробелы, лишние пробелы."""
    if value is None:
        return ""
    return re.sub(r"\s+", " ", str(value).replace("\u00a0", " ")).strip()


def number(value: object, percent: bool = False) -> Decimal:
    """Преобразует число из Excel, поддерживая запятую и знак процента."""
    if isinstance(value, (int, float)):
        return Decimal(str(value))
    raw = text(value).replace("%", "").replace(" ", "").replace(",", ".")
    try:
        return Decimal(raw)
    except InvalidOperation as error:
        raise ValueError(f"Не удалось разобрать число: {value!r}") from error


def sql_string(value: str) -> str:
    """Экранирует строку для T-SQL."""
    return "N'" + value.replace("'", "''") + "'"


def sql_number(value: Decimal) -> str:
    """Печатает число без экспоненты и лишних нулей."""
    normalized = value.normalize()
    if normalized == normalized.to_integral():
        return str(int(normalized))
    return format(normalized, "f")


def read_rows(filename: str) -> list[list[object]]:
    """Возвращает строки листа без заголовка."""
    workbook = openpyxl.load_workbook(SOURCE / filename, data_only=True, read_only=True)
    sheet = workbook.worksheets[0]
    rows = [list(row) for row in sheet.iter_rows(values_only=True)]
    workbook.close()
    header, body = rows[0], rows[1:]
    cleaned = [row for row in body if any(cell not in (None, "") for cell in row)]
    print(f"  {filename}: {len(cleaned)} строк, столбцы: {', '.join(text(h) for h in header)}")
    return cleaned


def load_material_types() -> list[dict]:
    """Типы материалов с процентом потери."""
    rows = read_rows("АД_Material_type_import.xlsx")
    return [
        {"id": index, "name": text(row[0]), "loss": number(row[1], percent=True)}
        for index, row in enumerate(rows, start=1)
    ]


def load_product_types() -> list[dict]:
    """Типы продукции с коэффициентом."""
    rows = read_rows("АД_Product_type_import.xlsx")
    return [
        {"id": index, "name": text(row[0]), "coefficient": number(row[1])}
        for index, row in enumerate(rows, start=1)
    ]


def load_materials() -> tuple[list[dict], list[dict]]:
    """Материалы и справочник единиц измерения."""
    rows = read_rows("АД_Materials_import.xlsx")
    materials: list[dict] = []
    units: list[dict] = []
    seen_units: dict[str, int] = {}

    for index, row in enumerate(rows, start=1):
        name = text(row[0])
        type_name = text(row[1])
        price = number(row[2])
        stock = number(row[3])
        minimum = number(row[4])
        package = number(row[5])
        unit_short = text(row[6])

        if unit_short not in seen_units:
            if unit_short not in UNIT_NAMES:
                raise ValueError(f"Неизвестная единица измерения: {unit_short!r}")
            unit_name, short = UNIT_NAMES[unit_short]
            units.append({"id": len(units) + 1, "name": unit_name, "short": short})
            seen_units[short] = units[-1]["id"]

        if price < 0 or stock < 0 or minimum < 0:
            raise ValueError(f"Отрицательное значение в строке {index + 1}: {name}")
        if package <= 0:
            raise ValueError(f"Количество в упаковке должно быть > 0: {name}")

        materials.append(
            {
                "id": index,
                "name": name,
                "type_name": type_name,
                "unit_short": unit_short,
                "price": price,
                "package": package,
                "stock": stock,
                "minimum": minimum,
            }
        )

    return materials, units


def load_products() -> list[dict]:
    """Продукция."""
    rows = read_rows("АД_Products_import.xlsx")
    return [
        {
            "id": index,
            "article": text(row[0]),
            "type_name": text(row[1]),
            "name": text(row[2]),
            "min_price": number(row[3]),
        }
        for index, row in enumerate(rows, start=1)
    ]


def load_recipes(materials: list[dict], products: list[dict]) -> list[dict]:
    """Рецептуры с проверкой ссылок."""
    rows = read_rows("АД_Material_products_import.xlsx")
    material_ids = {item["name"]: item["id"] for item in materials}
    product_ids = {item["name"]: item["id"] for item in products}
    recipes: list[dict] = []

    for index, row in enumerate(rows, start=1):
        material_name = text(row[0])
        product_name = text(row[1])
        quantity = number(row[2])
        if material_name not in material_ids:
            raise ValueError(f"Рецептура {index + 1}: неизвестный материал {material_name!r}")
        if product_name not in product_ids:
            raise ValueError(f"Рецептура {index + 1}: неизвестная продукция {product_name!r}")
        if quantity <= 0:
            raise ValueError(f"Рецептура {index + 1}: количество должно быть > 0")
        recipes.append(
            {
                "material_id": material_ids[material_name],
                "product_id": product_ids[product_name],
                "quantity": quantity,
            }
        )

    return recipes


def build_sql(
    material_types: list[dict],
    units: list[dict],
    product_types: list[dict],
    materials: list[dict],
    products: list[dict],
    recipes: list[dict],
) -> str:
    """Собирает текст скрипта наполнения."""
    type_ids = {item["name"]: item["id"] for item in material_types}
    unit_ids = {item["short"]: item["id"] for item in units}
    product_type_ids = {item["name"]: item["id"] for item in product_types}

    lines: list[str] = [
        "-- =============================================================================",
        "--  «Арома Дом» — данные заказчика, загруженные в схему AromaDom",
        "--  Источник: пять книг Excel с пометкой import (db/source)",
        "--  Сгенерировано скриптом tools/generate_seed_sql.py",
        "-- =============================================================================",
        "",
        "USE AromaDom;",
        "GO",
        "SET NOCOUNT ON;",
        "GO",
        "",
        "-- Типы материалов -----------------------------------------------------------",
        "SET IDENTITY_INSERT dbo.material_type ON;",
        "INSERT INTO dbo.material_type (material_type_id, name, loss_percent) VALUES",
    ]
    lines.append(
        ",\n".join(
            f"    ({item['id']}, {sql_string(item['name'])}, {sql_number(item['loss'])})"
            for item in material_types
        )
        + ";"
    )
    lines += ["SET IDENTITY_INSERT dbo.material_type OFF;", "GO", ""]

    lines += ["-- Единицы измерения ---------------------------------------------------------", "SET IDENTITY_INSERT dbo.unit ON;",
              "INSERT INTO dbo.unit (unit_id, name, short_name) VALUES"]
    lines.append(
        ",\n".join(
            f"    ({item['id']}, {sql_string(item['name'])}, {sql_string(item['short'])})" for item in units
        )
        + ";"
    )
    lines += ["SET IDENTITY_INSERT dbo.unit OFF;", "GO", ""]

    lines += ["-- Типы продукции ------------------------------------------------------------",
              "SET IDENTITY_INSERT dbo.product_type ON;",
              "INSERT INTO dbo.product_type (product_type_id, name, coefficient) VALUES"]
    lines.append(
        ",\n".join(
            f"    ({item['id']}, {sql_string(item['name'])}, {sql_number(item['coefficient'])})"
            for item in product_types
        )
        + ";"
    )
    lines += ["SET IDENTITY_INSERT dbo.product_type OFF;", "GO", ""]

    lines += ["-- Материалы -----------------------------------------------------------------", "SET IDENTITY_INSERT dbo.material ON;",
              "INSERT INTO dbo.material (material_id, material_type_id, unit_id, name, price,"
              " package_quantity, stock_quantity, min_quantity) VALUES"]
    lines.append(
        ",\n".join(
            "    ({id}, {type_id}, {unit_id}, {name}, {price}, {package}, {stock}, {minimum})".format(
                id=item["id"],
                type_id=type_ids[item["type_name"]],
                unit_id=unit_ids[item["unit_short"]],
                name=sql_string(item["name"]),
                price=sql_number(item["price"]),
                package=sql_number(item["package"]),
                stock=sql_number(item["stock"]),
                minimum=sql_number(item["minimum"]),
            )
            for item in materials
        )
        + ";"
    )
    lines += ["SET IDENTITY_INSERT dbo.material OFF;", "GO", ""]

    lines += ["-- Продукция -----------------------------------------------------------------", "SET IDENTITY_INSERT dbo.product ON;",
              "INSERT INTO dbo.product (product_id, product_type_id, article, name, min_price) VALUES"]
    lines.append(
        ",\n".join(
            "    ({id}, {type_id}, {article}, {name}, {price})".format(
                id=item["id"],
                type_id=product_type_ids[item["type_name"]],
                article=sql_string(item["article"]),
                name=sql_string(item["name"]),
                price=sql_number(item["min_price"]),
            )
            for item in products
        )
        + ";"
    )
    lines += ["SET IDENTITY_INSERT dbo.product OFF;", "GO", ""]

    lines += ["-- Рецептуры -----------------------------------------------------------------",
              "INSERT INTO dbo.material_product (material_id, product_id, quantity) VALUES"]
    lines.append(
        ",\n".join(
            f"    ({item['material_id']}, {item['product_id']}, {sql_number(item['quantity'])})" for item in recipes
        )
        + ";"
    )
    lines += ["GO", ""]

    lines += [
        "-- Контроль наполнения -------------------------------------------------------",
        "SELECT N'Типы материалов' AS entity, COUNT(*) AS rows_count FROM dbo.material_type",
        "UNION ALL SELECT N'Единицы измерения', COUNT(*) FROM dbo.unit",
        "UNION ALL SELECT N'Материалы', COUNT(*) FROM dbo.material",
        "UNION ALL SELECT N'Типы продукции', COUNT(*) FROM dbo.product_type",
        "UNION ALL SELECT N'Продукция', COUNT(*) FROM dbo.product",
        "UNION ALL SELECT N'Рецептуры', COUNT(*) FROM dbo.material_product;",
        "GO",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    """Читает файлы, проверяет данные и пишет db/02_seed.sql."""
    print("Чтение файлов заказчика:")
    material_types = load_material_types()
    units_rows = read_rows("АД_Materials_import.xlsx")
    product_types = load_product_types()
    materials, units = load_materials()
    products = load_products()
    recipes = load_recipes(materials, products)

    # Дополнительные проверки целостности до записи в БД.
    type_names = {item["name"] for item in material_types}
    for item in materials:
        if item["type_name"] not in type_names:
            raise ValueError(f"Неизвестный тип материала: {item['type_name']!r}")
    product_type_names = {item["name"] for item in product_types}
    for item in products:
        if item["type_name"] not in product_type_names:
            raise ValueError(f"Неизвестный тип продукции: {item['type_name']!r}")
    if len({item["name"] for item in materials}) != len(materials):
        raise ValueError("Повторяются наименования материалов")
    if len({item["article"] for item in products}) != len(products):
        raise ValueError("Повторяются артикулы продукции")

    OUTPUT.write_text(
        build_sql(material_types, units, product_types, materials, products, recipes),
        encoding="utf-8",
    )
    print(
        f"\nГотово: {OUTPUT}\n"
        f"  типы материалов: {len(material_types)}\n"
        f"  единицы измерения: {len(units)}\n"
        f"  материалы: {len(materials)}\n"
        f"  типы продукции: {len(product_types)}\n"
        f"  продукция: {len(products)}\n"
        f"  рецептуры: {len(recipes)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
