namespace WebApplication8.Data
{
    /// <summary>Справочные данные, необходимые методу расчёта продукции.</summary>
    public interface IProductLookup
    {
        /// <summary>Коэффициент типа продукции или null, если тип не найден.</summary>
        decimal? GetProductTypeCoefficient(int productTypeId);

        /// <summary>Процент потери сырья для типа материала или null.</summary>
        decimal? GetMaterialTypeLoss(int materialTypeId);
    }
}
