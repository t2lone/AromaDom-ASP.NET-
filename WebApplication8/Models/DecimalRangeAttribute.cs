using System;
using System.ComponentModel.DataAnnotations;

namespace WebApplication8.Models
{
    /// <summary>
    /// Проверка диапазона для decimal с границами, заданными в коде.
    /// Штатный RangeAttribute с typeof(decimal) разбирает границы в текущей
    /// культуре и падает на «0.001» при ru-RU, поэтому используется свой атрибут.
    /// </summary>
    [AttributeUsage(AttributeTargets.Property | AttributeTargets.Field | AttributeTargets.Parameter, AllowMultiple = false)]
    public sealed class DecimalRangeAttribute : ValidationAttribute
    {
        private readonly decimal _minimum;
        private readonly decimal _maximum;

        public DecimalRangeAttribute(double minimum, double maximum)
        {
            _minimum = (decimal)minimum;
            _maximum = (decimal)maximum;
        }

        public override bool IsValid(object value)
        {
            if (value == null)
            {
                return true;
            }

            if (!(value is decimal))
            {
                return false;
            }

            decimal number = (decimal)value;
            return number >= _minimum && number <= _maximum;
        }
    }
}
