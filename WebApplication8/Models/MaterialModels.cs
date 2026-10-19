using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace WebApplication8.Models
{
    /// <summary>Карточка материала в списке (данные представления v_material_card).</summary>
    public class MaterialCard
    {
        public int MaterialId { get; set; }
        public int MaterialTypeId { get; set; }
        public string Name { get; set; }
        public string MaterialTypeName { get; set; }
        public string UnitShortName { get; set; }
        public decimal Price { get; set; }
        public decimal PackageQuantity { get; set; }
        public decimal StockQuantity { get; set; }
        public decimal MinQuantity { get; set; }
        public decimal RequiredQuantity { get; set; }
        public bool IsBelowMin { get; set; }
    }

    /// <summary>Категория материалов на главной странице.</summary>
    public class CategoryGroup
    {
        public int MaterialTypeId { get; set; }
        public string Name { get; set; }
        public IList<MaterialCard> Items { get; set; }
    }

    /// <summary>Полные данные материала для формы редактирования.</summary>
    public class Material
    {
        public int MaterialId { get; set; }
        public int MaterialTypeId { get; set; }
        public int UnitId { get; set; }
        public string Name { get; set; }
        public decimal Price { get; set; }
        public decimal PackageQuantity { get; set; }
        public decimal StockQuantity { get; set; }
        public decimal MinQuantity { get; set; }
        public string Description { get; set; }
    }

    /// <summary>Строка справочника: тип материала, тип продукции или единица измерения.</summary>
    public class LookupItem
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public string ShortName { get; set; }
        public decimal Value { get; set; }

        public string DisplayName
        {
            get { return string.IsNullOrEmpty(ShortName) ? Name : Name + " (" + ShortName + ")"; }
        }
    }

    /// <summary>Модель формы добавления и редактирования материала.</summary>
    public class MaterialFormModel
    {
        public int? MaterialId { get; set; }

        [Required(ErrorMessage = "Выберите тип материала.")]
        [Display(Name = "Тип материала")]
        public int? MaterialTypeId { get; set; }

        [Required(ErrorMessage = "Укажите наименование материала.")]
        [StringLength(120, ErrorMessage = "Наименование не должно быть длиннее 120 символов.")]
        [Display(Name = "Наименование")]
        public string Name { get; set; }

        [Required(ErrorMessage = "Укажите цену единицы материала.")]
        [DecimalRange(0, 1000000000, ErrorMessage = "Цена не может быть отрицательной.")]
        [Display(Name = "Цена единицы материала, р")]
        public decimal? Price { get; set; }

        [Required(ErrorMessage = "Выберите единицу измерения.")]
        [Display(Name = "Единица измерения")]
        public int? UnitId { get; set; }

        [Required(ErrorMessage = "Укажите количество в упаковке.")]
        [DecimalRange(0.001, 1000000000, ErrorMessage = "Количество в упаковке должно быть больше нуля.")]
        [Display(Name = "Количество в упаковке")]
        public decimal? PackageQuantity { get; set; }

        [Required(ErrorMessage = "Укажите количество на складе.")]
        [DecimalRange(0, 1000000000, ErrorMessage = "Количество на складе не может быть отрицательным.")]
        [Display(Name = "Количество на складе")]
        public decimal? StockQuantity { get; set; }

        [Required(ErrorMessage = "Укажите минимальное количество.")]
        [DecimalRange(0, 1000000000, ErrorMessage = "Минимальное количество не может быть отрицательным.")]
        [Display(Name = "Минимальное количество")]
        public decimal? MinQuantity { get; set; }

        public IEnumerable<System.Web.Mvc.SelectListItem> MaterialTypes { get; set; }
        public IEnumerable<System.Web.Mvc.SelectListItem> Units { get; set; }
    }

    /// <summary>Продукция, в рецептуре которой используется материал.</summary>
    public class ProductUsage
    {
        public int ProductId { get; set; }
        public string Article { get; set; }
        public string ProductName { get; set; }
        public string ProductTypeName { get; set; }
        public decimal Quantity { get; set; }
    }

    /// <summary>Модель страницы «Продукция по материалу».</summary>
    public class ProductsPageModel
    {
        public Material Material { get; set; }
        public string MaterialTypeName { get; set; }
        public string UnitShortName { get; set; }
        public IList<ProductUsage> Items { get; set; }
        public decimal Total { get; set; }
    }

    /// <summary>Модель калькулятора выхода продукции.</summary>
    public class CalculatorModel
    {
        [Required(ErrorMessage = "Выберите тип продукции.")]
        [Display(Name = "Тип продукции")]
        public int? ProductTypeId { get; set; }

        [Required(ErrorMessage = "Выберите тип материала.")]
        [Display(Name = "Тип материала")]
        public int? MaterialTypeId { get; set; }

        [Required(ErrorMessage = "Укажите количество сырья.")]
        [Range(1, 1000000, ErrorMessage = "Количество сырья — целое число больше нуля.")]
        [Display(Name = "Количество сырья")]
        public int? RawAmount { get; set; }

        [Required(ErrorMessage = "Укажите первый параметр.")]
        [Range(0.001, 1000000, ErrorMessage = "Параметр должен быть положительным.")]
        [Display(Name = "Параметр продукции 1")]
        public double? Param1 { get; set; }

        [Required(ErrorMessage = "Укажите второй параметр.")]
        [Range(0.001, 1000000, ErrorMessage = "Параметр должен быть положительным.")]
        [Display(Name = "Параметр продукции 2")]
        public double? Param2 { get; set; }

        public int? Result { get; set; }
        public string ResultNote { get; set; }
        public IEnumerable<System.Web.Mvc.SelectListItem> ProductTypes { get; set; }
        public IEnumerable<System.Web.Mvc.SelectListItem> MaterialTypes { get; set; }
    }
}
