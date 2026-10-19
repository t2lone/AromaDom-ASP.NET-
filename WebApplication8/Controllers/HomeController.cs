using System.Collections.Generic;
using System.Linq;
using System.Web.Mvc;
using WebApplication8.Data;
using WebApplication8.Models;

namespace WebApplication8.Controllers
{
    /// <summary>Главная страница: материалы, сгруппированные по категориям.</summary>
    public class HomeController : Controller
    {
        private readonly MaterialRepository _repository;

        public HomeController()
            : this(new MaterialRepository())
        {
        }

        public HomeController(MaterialRepository repository)
        {
            _repository = repository;
        }

        public ActionResult Index()
        {
            List<MaterialCard> materials = _repository.GetMaterials(null);

            List<CategoryGroup> groups = materials
                .GroupBy(item => new { item.MaterialTypeId, item.MaterialTypeName })
                .OrderBy(group => group.Key.MaterialTypeName)
                .Select(group => new CategoryGroup
                {
                    MaterialTypeId = group.Key.MaterialTypeId,
                    Name = group.Key.MaterialTypeName,
                    Items = group.OrderBy(item => item.Name).ToList()
                })
                .ToList();

            ViewBag.Total = materials.Count;
            ViewBag.Categories = groups.Count;

            return View(groups);
        }
    }
}
