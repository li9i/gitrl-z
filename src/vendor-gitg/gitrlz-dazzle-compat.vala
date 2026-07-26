/*
 * gitrl-z compatibility shim for libdazzle.
 *
 * The vendored gitg font manager (gitg-font-manager.vala, left byte-for-byte as
 * upstream wrote it) calls Dazzle.pango_font_description_to_css to turn the
 * configured monospace font into a CSS fragment for a GtkCssProvider. libdazzle
 * was removed from Ubuntu 26.04, and this one function was the only thing
 * gitrl-z used from the whole library, so rather than carry the dependency we
 * provide the function ourselves. Vala namespaces are open, so re-declaring it
 * here satisfies the vendored call site with no change to it.
 *
 * The output mirrors dzl_pango_font_description_to_css so behaviour is
 * unchanged: a run of "key:value;" declarations, only for the fields the font
 * description actually sets.
 */
namespace Dazzle
{
	public string pango_font_description_to_css(Pango.FontDescription font_desc)
	{
		var str = new StringBuilder();
		var mask = font_desc.get_set_fields();

		if ((mask & Pango.FontMask.FAMILY) != 0)
		{
			str.append_printf("font-family:\"%s\";", font_desc.get_family());
		}

		if ((mask & Pango.FontMask.STYLE) != 0)
		{
			switch (font_desc.get_style())
			{
				case Pango.Style.NORMAL:  str.append("font-style:normal;");  break;
				case Pango.Style.OBLIQUE: str.append("font-style:oblique;"); break;
				case Pango.Style.ITALIC:  str.append("font-style:italic;");  break;
			}
		}

		if ((mask & Pango.FontMask.VARIANT) != 0)
		{
			switch (font_desc.get_variant())
			{
				case Pango.Variant.NORMAL:     str.append("font-variant:normal;");     break;
				case Pango.Variant.SMALL_CAPS: str.append("font-variant:small-caps;"); break;
				default: break;
			}
		}

		if ((mask & Pango.FontMask.WEIGHT) != 0)
		{
			str.append_printf("font-weight:%d;", (int) font_desc.get_weight());
		}

		if ((mask & Pango.FontMask.STRETCH) != 0)
		{
			switch (font_desc.get_stretch())
			{
				case Pango.Stretch.ULTRA_CONDENSED: str.append("font-stretch:ultra-condensed;"); break;
				case Pango.Stretch.EXTRA_CONDENSED: str.append("font-stretch:extra-condensed;"); break;
				case Pango.Stretch.CONDENSED:       str.append("font-stretch:condensed;");       break;
				case Pango.Stretch.SEMI_CONDENSED:  str.append("font-stretch:semi-condensed;");  break;
				case Pango.Stretch.NORMAL:          str.append("font-stretch:normal;");          break;
				case Pango.Stretch.SEMI_EXPANDED:   str.append("font-stretch:semi-expanded;");   break;
				case Pango.Stretch.EXPANDED:        str.append("font-stretch:expanded;");        break;
				case Pango.Stretch.EXTRA_EXPANDED:  str.append("font-stretch:extra-expanded;");  break;
				case Pango.Stretch.ULTRA_EXPANDED:  str.append("font-stretch:ultra-expanded;");  break;
			}
		}

		if ((mask & Pango.FontMask.SIZE) != 0)
		{
			var size = font_desc.get_size() / Pango.SCALE;
			if (font_desc.get_size_is_absolute())
			{
				str.append_printf("font-size:%dpx;", size);
			}
			else
			{
				str.append_printf("font-size:%dpt;", size);
			}
		}

		return str.str;
	}
}
