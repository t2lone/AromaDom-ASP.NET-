using System;
using System.Collections.Generic;
using System.Linq;
using System.Web.Mvc;
using WebApplication8.Data;
using WebApplication8.Models;
using WebApplication8.Services;

namespace WebApplication8.Controllers
{
    /// <summary>Демонстрация метода расчёта количества продукции (модуль 4).</summary>
    public class CalculatorController : Controller
    {
        private readonly MaterialRepository _repository;

        public CalculatorController()
            : this(new MaterialRepository())
        {
        }

        public CalculatorController(MaterialRepository repository)
        {
            _repository = repository;
        }

        public ActionResult Index()
        {
            List<LookupItem> productTypes = _repository.GetProductTypes();
            List<LookupItem> materialTypes = _repository.GetMaterialTypes();
            LookupItem firstProductType = productTypes.FirstOrDefault();
            LookupItem firstMaterialType = materialTypes.FirstOrDefault();

            var model = new CalculatorModel
            {
                ProductTypeId = firstProductType == null ? (int?)null : firstProductType.Id,
                MaterialTypeId = firstMaterialType == null ? (int?)null : firstMaterialType.Id,
                RawAmount = 10,
                Param1 = 0.18,
                Param2 = 1.0
            };
            FillLookups(model);
            return View(model);
        }

        [HttpPost]
        [ValidateAntiForgeryToken]
        public ActionResult Index(CalculatorModel model)
        {
            FillLookups(model);
            if (!ModelState.IsValid)
            {
                return View(model);
            }

            int result = ProductCalculator.Calculate(
                model.ProductTypeId.Value,
                model.MaterialTypeId.Value,
                model.RawAmount.Value,
                model.Param1.Value,
                model.Param2.Value,
                _repository);

            if (result < 0)
            {
                ModelState.AddModelError(
                    string.Empty,
                    "Расчёт невозможен: проверьте выбранные типы и введённые значения. Метод вернул -1.");
                return View(model);
            }

            decimal coefficient = _repository.GetProductTypeCoefficient(model.ProductTypeId.Value) ?? 0;
            decimal loss = _repository.GetMaterialTypeLoss(model.MaterialTypeId.Value) ?? 0;
            double consumption = model.Param1.Value * model.Param2.Value * (double)coefficient;
            double usable = model.RawAmount.Value * (1.0 - (double)loss / 100.0);

            model.Result = result;
            model.ResultNote = string.Format(
                "Полезное сырьё: {0:0.###} ед. · расход на изделие: {1:0.###} ед. · коэффициент типа: {2:0.###} · потери: {3:0.##}%",
                usable,
                consumption,
                coefficient,
                loss);

            return View(model);
        }

        private void FillLookups(CalculatorModel model)
        {
            List<LookupItem> productTypes = _repository.GetProductTypes();
            List<LookupItem> materialTypes = _repository.GetMaterialTypes();

            model.ProductTypes = productTypes
                .Select(item => new SelectListItem
                {
                    Value = item.Id.ToString(),
                    Text = item.Name + " · коэффициент " + item.Value.ToString("0.###")
                })
                .ToList();

            model.MaterialTypes = materialTypes
                .Select(item => new SelectListItem
                {
                    Value = item.Id.ToString(),
                    Text = item.Name + " · потери " + item.Value.ToString("0.##") + "%"
                })
                .ToList();
        }
    }
}
