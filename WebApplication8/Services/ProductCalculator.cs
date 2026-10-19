using System;
using WebApplication8.Data;

namespace WebApplication8.Services
{
    /// <summary>
    /// Расчёт количества продукции из заданного количества сырья (модуль 4).
    /// Учитывает коэффициент типа продукции и процент потери сырья.
    /// </summary>
    public static class ProductCalculator
    {
        /// <summary>
        /// Считает, сколько целых изделий получится из заданного количества сырья.
        /// </summary>
        /// <param name="productTypeId">Идентификатор типа продукции (целое &gt; 0).</param>
        /// <param name="materialTypeId">Идентификатор типа материала (целое &gt; 0).</param>
        /// <param name="rawAmount">Количество сырья в единицах материала (целое &gt; 0).</param>
        /// <param name="param1">Первый параметр продукции (вещественное &gt; 0).</param>
        /// <param name="param2">Второй параметр продукции (вещественное &gt; 0).</param>
        /// <param name="lookup">Источник коэффициента типа и процента потерь.</param>
        /// <returns>Количество продукции или -1, если данные некорректны.</returns>
        public static int Calculate(
            int productTypeId,
            int materialTypeId,
            int rawAmount,
            double param1,
            double param2,
            IProductLookup lookup)
        {
            if (lookup == null)
            {
                return -1;
            }

            if (productTypeId <= 0 || materialTypeId <= 0 || rawAmount <= 0)
            {
                return -1;
            }

            if (!IsPositiveNumber(param1) || !IsPositiveNumber(param2))
            {
                return -1;
            }

            decimal? coefficient = lookup.GetProductTypeCoefficient(productTypeId);
            decimal? lossPercent = lookup.GetMaterialTypeLoss(materialTypeId);

            if (!coefficient.HasValue || !lossPercent.HasValue)
            {
                return -1;
            }

            if (coefficient.Value <= 0 || lossPercent.Value < 0 || lossPercent.Value >= 100)
            {
                return -1;
            }

            double consumptionPerUnit = param1 * param2 * (double)coefficient.Value;
            if (consumptionPerUnit <= 0)
            {
                return -1;
            }

            double usableRaw = rawAmount * (1.0 - (double)lossPercent.Value / 100.0);
            double quantity = Math.Floor(usableRaw / consumptionPerUnit + 1e-9);

            if (quantity < 0 || quantity > int.MaxValue)
            {
                return -1;
            }

            return (int)quantity;
        }

        private static bool IsPositiveNumber(double value)
        {
            return !double.IsNaN(value) && !double.IsInfinity(value) && value > 0;
        }
    }
}
