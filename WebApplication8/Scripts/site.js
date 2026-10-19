// Проверка чисел с запятой: в русской локали пользователь вводит 890,00,
// а jQuery Validate по умолчанию ожидает точку. Расширяем правила.
(function ($) {
    if (!$ || !$.validator) {
        return;
    }

    $.validator.methods.number = function (value, element) {
        return this.optional(element) || /^-?(?:\d+|\d{1,3}(?:[\s\u00A0]\d{3})+)?(?:[.,]\d+)?$/.test(value);
    };

    $.validator.methods.range = function (value, element, param) {
        if (this.optional(element)) {
            return true;
        }
        var number = parseFloat(String(value).replace(/\s/g, "").replace(",", "."));
        return !isNaN(number) && number >= param[0] && number <= param[1];
    };

    $.validator.methods.min = function (value, element, param) {
        var number = parseFloat(String(value).replace(/\s/g, "").replace(",", "."));
        return this.optional(element) || (!isNaN(number) && number >= param);
    };

    $.validator.methods.max = function (value, element, param) {
        var number = parseFloat(String(value).replace(/\s/g, "").replace(",", "."));
        return this.optional(element) || (!isNaN(number) && number <= param);
    };
})(window.jQuery);
