using System;
using System.Collections.Generic;
using System.Data.SqlClient;
using System.Linq;
using System.Web.Mvc;
using WebApplication8.Data;
using WebApplication8.Models;

namespace WebApplication8.Controllers
{
    /// <summary>Подсистема учёта материалов: список, добавление, редактирование, продукция.</summary>
    public class MaterialsController : Controller
    {
        private readonly MaterialRepository _repository;

        public MaterialsController()
            : this(new MaterialRepository())
        {
        }

        public MaterialsController(MaterialRepository repository)
        {
            _repository = repository;
        }

        /// <summary>Каталог: все материалы с поиском и фильтром по категории.</summary>
        public ActionResult Index(string search, int? typeId)
        {
            ViewBag.Search = search;
            ViewBag.TypeId = typeId;
            ViewBag.TypeOptions = _repository.GetMaterialTypes()
                .Select(item => new SelectListItem
                {
                    Value = item.Id.ToString(),
                    Text = item.Name,
                    Selected = typeId.HasValue && typeId.Value == item.Id
                })
                .ToList();

            List<MaterialCard> materials = _repository.GetMaterials(search, typeId);
            return View(materials);
        }

        /// <summary>Форма добавления материала.</summary>
        public ActionResult Create()
        {
            var model = new MaterialFormModel
            {
                PackageQuantity = 1,
                StockQuantity = 0,
                MinQuantity = 0
            };
            FillLookups(model);
            return View("Form", model);
        }

        /// <summary>Сохранение нового материала.</summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Create(MaterialFormModel model)
        {
            FillLookups(model);
            Normalize(model);
            ValidateBusinessRules(model, null);

            if (!ModelState.IsValid)
            {
                return View("Form", model);
            }

            try
            {
                _repository.InsertMaterial(ToMaterial(model));
                TempData["Success"] = "Материал «" + model.Name + "» добавлен.";
                return RedirectToAction("Index");
            }
            catch (SqlException error)
            {
                AddDatabaseError(error);
                return View("Form", model);
            }
        }

        /// <summary>Форма редактирования материала.</summary>
        public ActionResult Edit(int id)
        {
            Material material = _repository.GetMaterial(id);
            if (material == null)
            {
                return HttpNotFound("Материал не найден.");
            }

            MaterialFormModel model = ToForm(material);
            FillLookups(model);
            return View("Form", model);
        }

        /// <summary>Сохранение изменений материала.</summary>
        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Edit(int id, MaterialFormModel model)
        {
            Material existing = _repository.GetMaterial(id);
            if (existing == null)
            {
                return HttpNotFound("Материал не найден.");
            }

            model.MaterialId = id;
            FillLookups(model);
            Normalize(model);
            ValidateBusinessRules(model, id);

            if (!ModelState.IsValid)
            {
                return View("Form", model);
            }

            try
            {
                _repository.UpdateMaterial(ToMaterial(model));
                TempData["Success"] = "Изменения материала «" + model.Name + "» сохранены.";
                return RedirectToAction("Index");
            }
            catch (SqlException error)
            {
                AddDatabaseError(error);
                return View("Form", model);
            }
        }

        /// <summary>Продукция, в рецептуре которой используется материал.</summary>
        public ActionResult Products(int id)
        {
            Material material = _repository.GetMaterial(id);
            if (material == null)
            {
                return HttpNotFound("Материал не найден.");
            }

            List<LookupItem> materialTypes = _repository.GetMaterialTypes();
            LookupItem type = materialTypes.FirstOrDefault(item => item.Id == material.MaterialTypeId);
            List<LookupItem> units = _repository.GetUnits();
            LookupItem unit = units.FirstOrDefault(item => item.Id == material.UnitId);

            var model = new ProductsPageModel
            {
                Material = material,
                MaterialTypeName = type == null ? string.Empty : type.Name,
                UnitShortName = unit == null ? string.Empty : unit.ShortName,
                Items = _repository.GetProductsForMaterial(id),
                Total = _repository.GetRequiredQuantity(id)
            };

            return View(model);
        }

        private void FillLookups(MaterialFormModel model)
        {
            model.MaterialTypes = _repository.GetMaterialTypes()
                .Select(item => new SelectListItem { Value = item.Id.ToString(), Text = item.Name })
                .ToList();
            model.Units = _repository.GetUnits()
                .Select(item => new SelectListItem { Value = item.Id.ToString(), Text = item.ShortName })
                .ToList();
        }

        private static void Normalize(MaterialFormModel model)
        {
            if (model.Name != null)
            {
                model.Name = string.Join(" ", model.Name.Split(new[] { ' ', '\t', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries));
            }
        }

        private void ValidateBusinessRules(MaterialFormModel model, int? excludeId)
        {
            if (model.Price.HasValue && decimal.Round(model.Price.Value, 2) != model.Price.Value)
            {
                ModelState.AddModelError("Price", "Цена должна иметь не более двух знаков после запятой.");
            }

            if (!string.IsNullOrWhiteSpace(model.Name) && _repository.NameExists(model.Name, excludeId))
            {
                ModelState.AddModelError("Name", "Материал с таким наименованием уже существует. Укажите другое наименование.");
            }
        }

        private void AddDatabaseError(SqlException error)
        {
            if (error.Number == 2601 || error.Number == 2627)
            {
                ModelState.AddModelError("Name", "Материал с таким наименованием уже существует. Укажите другое наименование.");
            }
            else if (error.Number == 547)
            {
                ModelState.AddModelError("", "Выбранный тип материала или единица измерения не существуют. Обновите страницу и выберите значение из списка.");
            }
            else if (error.Number == 515)
            {
                ModelState.AddModelError("", "Не заполнено обязательное поле. Проверьте форму и повторите сохранение.");
            }
            else
            {
                ModelState.AddModelError("", "Не удалось сохранить материал: база данных вернула ошибку. Попробуйте ещё раз.");
            }
        }

        private static Material ToMaterial(MaterialFormModel model)
        {
            return new Material
            {
                MaterialId = model.MaterialId ?? 0,
                MaterialTypeId = model.MaterialTypeId.Value,
                UnitId = model.UnitId.Value,
                Name = model.Name,
                Price = Math.Round(model.Price.Value, 2, MidpointRounding.AwayFromZero),
                PackageQuantity = model.PackageQuantity.Value,
                StockQuantity = model.StockQuantity.Value,
                MinQuantity = model.MinQuantity.Value
            };
        }

        private static MaterialFormModel ToForm(Material material)
        {
            return new MaterialFormModel
            {
                MaterialId = material.MaterialId,
                Name = material.Name,
                MaterialTypeId = material.MaterialTypeId,
                UnitId = material.UnitId,
                Price = material.Price,
                PackageQuantity = material.PackageQuantity,
                StockQuantity = material.StockQuantity,
                MinQuantity = material.MinQuantity
            };
        }
    }
}
