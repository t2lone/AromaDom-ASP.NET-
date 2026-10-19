using System;
using System.Collections.Generic;
using System.Configuration;
using System.Data;
using System.Data.SqlClient;
using WebApplication8.Models;

namespace WebApplication8.Data
{
    /// <summary>Доступ к данным подсистемы учёта материалов.</summary>
    public class MaterialRepository : IProductLookup
    {
        private readonly string _connectionString;

        public MaterialRepository()
            : this(ConfigurationManager.ConnectionStrings["AromaDom"].ConnectionString)
        {
        }

        public MaterialRepository(string connectionString)
        {
            if (string.IsNullOrWhiteSpace(connectionString))
            {
                throw new ArgumentException("Не задана строка подключения к базе AromaDom.", "connectionString");
            }

            _connectionString = connectionString;
        }

        private SqlConnection CreateConnection()
        {
            return new SqlConnection(_connectionString);
        }

        /// <summary>Список карточек материалов с поиском по наименованию и типу.</summary>
        public List<MaterialCard> GetMaterials(string search, int? materialTypeId = null)
        {
            const string sql = @"
SELECT material_id, material_type_id, name, material_type_name, unit_short_name, price,
       package_quantity, stock_quantity, min_quantity, required_quantity, is_below_min
  FROM dbo.v_material_card
 WHERE (@search IS NULL
        OR name LIKE N'%' + @search + N'%'
        OR material_type_name LIKE N'%' + @search + N'%')
   AND (@typeId IS NULL OR material_type_id = @typeId)
 ORDER BY name;";

            var result = new List<MaterialCard>();
            using (var connection = CreateConnection())
            using (var command = new SqlCommand(sql, connection))
            {
                command.Parameters.Add("@search", SqlDbType.NVarChar, 120).Value =
                    string.IsNullOrWhiteSpace(search) ? (object)DBNull.Value : search.Trim();
                command.Parameters.Add("@typeId", SqlDbType.Int).Value =
                    materialTypeId.HasValue ? (object)materialTypeId.Value : DBNull.Value;

                connection.Open();
                using (var reader = command.ExecuteReader())
                {
                    while (reader.Read())
                    {
                        result.Add(new MaterialCard
                        {
                            MaterialId = reader.GetInt32(0),
                            MaterialTypeId = reader.GetInt32(1),
                            Name = reader.GetString(2),
                            MaterialTypeName = reader.GetString(3),
                            UnitShortName = reader.GetString(4),
                            Price = reader.GetDecimal(5),
                            PackageQuantity = reader.GetDecimal(6),
                            StockQuantity = reader.GetDecimal(7),
                            MinQuantity = reader.GetDecimal(8),
                            RequiredQuantity = reader.GetDecimal(9),
                            IsBelowMin = reader.GetBoolean(10)
                        });
                    }
                }
            }

            return result;
        }

        /// <summary>Материал по идентификатору или null, если запись не найдена.</summary>
        public Material GetMaterial(int materialId)
        {
            const string sql = @"
SELECT material_id, material_type_id, unit_id, name, price, package_quantity,
       stock_quantity, min_quantity, ISNULL(description, N'') AS description
  FROM dbo.material
 WHERE material_id = @id;";

            using (var connection = CreateConnection())
            using (var command = new SqlCommand(sql, connection))
            {
                command.Parameters.Add("@id", SqlDbType.Int).Value = materialId;
                connection.Open();
                using (var reader = command.ExecuteReader())
                {
                    if (!reader.Read())
                    {
                        return null;
                    }

                    return new Material
                    {
                        MaterialId = reader.GetInt32(0),
                        MaterialTypeId = reader.GetInt32(1),
                        UnitId = reader.GetInt32(2),
                        Name = reader.GetString(3),
                        Price = reader.GetDecimal(4),
                        PackageQuantity = reader.GetDecimal(5),
                        StockQuantity = reader.GetDecimal(6),
                        MinQuantity = reader.GetDecimal(7),
                        Description = reader.GetString(8)
                    };
                }
            }
        }

        /// <summary>Справочник типов материалов.</summary>
        public List<LookupItem> GetMaterialTypes()
        {
            return GetLookup("SELECT material_type_id, name, N'' AS short_name, loss_percent FROM dbo.material_type ORDER BY name;");
        }

        /// <summary>Справочник единиц измерения.</summary>
        public List<LookupItem> GetUnits()
        {
            return GetLookup("SELECT unit_id, name, short_name, 0 FROM dbo.unit ORDER BY unit_id;");
        }

        /// <summary>Справочник типов продукции.</summary>
        public List<LookupItem> GetProductTypes()
        {
            return GetLookup("SELECT product_type_id, name, N'' AS short_name, coefficient FROM dbo.product_type ORDER BY name;");
        }

        private List<LookupItem> GetLookup(string sql)
        {
            var result = new List<LookupItem>();
            using (var connection = CreateConnection())
            using (var command = new SqlCommand(sql, connection))
            {
                connection.Open();
                using (var reader = command.ExecuteReader())
                {
                    while (reader.Read())
                    {
                        result.Add(new LookupItem
                        {
                            Id = reader.GetInt32(0),
                            Name = reader.GetString(1),
                            ShortName = reader.GetString(2),
                            Value = reader.IsDBNull(3) ? 0 : Convert.ToDecimal(reader.GetValue(3))
                        });
                    }
                }
            }

            return result;
        }

        /// <summary>Добавляет материал и возвращает его идентификатор.</summary>
        public int InsertMaterial(Material material)
        {
            const string sql = @"
INSERT INTO dbo.material (material_type_id, unit_id, name, price,
                          package_quantity, stock_quantity, min_quantity, description)
OUTPUT INSERTED.material_id
VALUES (@type, @unit, @name, @price, @package, @stock, @min, @description);";

            using (var connection = CreateConnection())
            using (var command = new SqlCommand(sql, connection))
            {
                AddMaterialParameters(command, material);
                connection.Open();
                return Convert.ToInt32(command.ExecuteScalar());
            }
        }

        /// <summary>Обновляет материал; изменение остатка попадает в историю через триггер.</summary>
        public void UpdateMaterial(Material material)
        {
            const string sql = @"
UPDATE dbo.material
   SET material_type_id = @type,
       unit_id = @unit,
       name = @name,
       price = @price,
       package_quantity = @package,
       stock_quantity = @stock,
       min_quantity = @min,
       description = @description
 WHERE material_id = @id;";

            using (var connection = CreateConnection())
            using (var command = new SqlCommand(sql, connection))
            {
                AddMaterialParameters(command, material);
                command.Parameters.Add("@id", SqlDbType.Int).Value = material.MaterialId;
                connection.Open();
                command.ExecuteNonQuery();
            }
        }

        private static void AddMaterialParameters(SqlCommand command, Material material)
        {
            command.Parameters.Add("@type", SqlDbType.Int).Value = material.MaterialTypeId;
            command.Parameters.Add("@unit", SqlDbType.Int).Value = material.UnitId;
            command.Parameters.Add("@name", SqlDbType.NVarChar, 120).Value = material.Name;
            command.Parameters.Add("@price", SqlDbType.Decimal).Value = material.Price;
            command.Parameters.Add("@package", SqlDbType.Decimal).Value = material.PackageQuantity;
            command.Parameters.Add("@stock", SqlDbType.Decimal).Value = material.StockQuantity;
            command.Parameters.Add("@min", SqlDbType.Decimal).Value = material.MinQuantity;
            command.Parameters.Add("@description", SqlDbType.NVarChar, 500).Value =
                string.IsNullOrEmpty(material.Description) ? (object)DBNull.Value : material.Description;
        }

        /// <summary>Проверяет уникальность наименования материала.</summary>
        public bool NameExists(string name, int? excludeMaterialId)
        {
            const string sql = @"
SELECT COUNT(*)
  FROM dbo.material
 WHERE name = @name
   AND (@exclude IS NULL OR material_id <> @exclude);";

            using (var connection = CreateConnection())
            using (var command = new SqlCommand(sql, connection))
            {
                command.Parameters.Add("@name", SqlDbType.NVarChar, 120).Value = name;
                command.Parameters.Add("@exclude", SqlDbType.Int).Value =
                    excludeMaterialId.HasValue ? (object)excludeMaterialId.Value : DBNull.Value;
                connection.Open();
                return Convert.ToInt32(command.ExecuteScalar()) > 0;
            }
        }

        /// <summary>Продукция, в рецептуре которой используется материал.</summary>
        public List<ProductUsage> GetProductsForMaterial(int materialId)
        {
            const string sql = @"
SELECT product_id, article, product_name, product_type_name, quantity
  FROM dbo.v_material_product
 WHERE material_id = @id
 ORDER BY product_name;";

            var result = new List<ProductUsage>();
            using (var connection = CreateConnection())
            using (var command = new SqlCommand(sql, connection))
            {
                command.Parameters.Add("@id", SqlDbType.Int).Value = materialId;
                connection.Open();
                using (var reader = command.ExecuteReader())
                {
                    while (reader.Read())
                    {
                        result.Add(new ProductUsage
                        {
                            ProductId = reader.GetInt32(0),
                            Article = reader.GetString(1),
                            ProductName = reader.GetString(2),
                            ProductTypeName = reader.GetString(3),
                            Quantity = reader.GetDecimal(4)
                        });
                    }
                }
            }

            return result;
        }

        /// <summary>Сумма норм расхода материала по всем рецептурам.</summary>
        public decimal GetRequiredQuantity(int materialId)
        {
            const string sql = "SELECT COALESCE(SUM(quantity), 0) FROM dbo.material_product WHERE material_id = @id;";

            using (var connection = CreateConnection())
            using (var command = new SqlCommand(sql, connection))
            {
                command.Parameters.Add("@id", SqlDbType.Int).Value = materialId;
                connection.Open();
                return Convert.ToDecimal(command.ExecuteScalar());
            }
        }

        /// <summary>Коэффициент типа продукции или null, если тип не найден.</summary>
        public decimal? GetProductTypeCoefficient(int productTypeId)
        {
            return GetNullableDecimal(
                "SELECT coefficient FROM dbo.product_type WHERE product_type_id = @id;",
                productTypeId);
        }

        /// <summary>Процент потери сырья для типа материала или null.</summary>
        public decimal? GetMaterialTypeLoss(int materialTypeId)
        {
            return GetNullableDecimal(
                "SELECT loss_percent FROM dbo.material_type WHERE material_type_id = @id;",
                materialTypeId);
        }

        private decimal? GetNullableDecimal(string sql, int id)
        {
            using (var connection = CreateConnection())
            using (var command = new SqlCommand(sql, connection))
            {
                command.Parameters.Add("@id", SqlDbType.Int).Value = id;
                connection.Open();
                var value = command.ExecuteScalar();
                return value == null || value == DBNull.Value ? (decimal?)null : Convert.ToDecimal(value);
            }
        }
    }
}
