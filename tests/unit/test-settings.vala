/*
 * This file is part of gitrl-z
 *
 * Copyright (C) 2026 alexandros filotheou
 *
 * gitrl-z is free software: you can redistribute it and/or modify it under the
 * terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 2 of the License, or (at your option) any later
 * version.
 *
 * gitrl-z is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along
 * with gitrl-z. If not, see <http://www.gnu.org/licenses/>.
 */

/*
 * The settings schema (spec FR-116).
 *
 * Every key gitrl-z reads must exist, with the documented type and default.
 * A missing schema key is not a graceful failure in GLib: it aborts the
 * process, so getting this wrong takes the whole application down at
 * startup rather than degrading.
 */

namespace GitrlzTest
{

private static Settings settings_for(string suffix)
{
	return new Settings("%s.%s".printf(Gitrlz.Config.APPLICATION_ID, suffix));
}

private static void test_interface_defaults()
{
	var s = settings_for("preferences.interface");

	assert_cmpstr(s.get_string("orientation"), CompareOperator.EQ, "vertical");
	assert_true(s.get_boolean("use-default-font"));
	assert_cmpstr(s.get_string("monospace-font-name"), CompareOperator.EQ, "Monospace 12");
	assert_true(s.get_boolean("enable-monitoring"));
}

private static void test_reflog_defaults()
{
	var s = settings_for("preferences.reflog");

	assert_cmpint(s.get_int("collapse-inactive-lanes"), CompareOperator.EQ, 2);
	assert_true(s.get_boolean("collapse-inactive-lanes-enabled"));
	// P-FR-22: the graph draws at most this many commits.
	assert_cmpint(s.get_int("commit-limit"), CompareOperator.EQ, 2000);
}

private static void test_window_state_defaults()
{
	var s = settings_for("state.window");

	assert_cmpint(s.get_int("state"), CompareOperator.EQ, 0);

	int width;
	int height;
	s.get_value("size").get("(ii)", out width, out height);

	assert_cmpint(width, CompareOperator.EQ, 1000);
	assert_cmpint(height, CompareOperator.EQ, 700);
}

private static void test_reflog_state_defaults()
{
	var s = settings_for("state.reflog");

	assert_cmpint(s.get_int("paned-sidebar-position"), CompareOperator.EQ, 200);
}

private static void test_values_round_trip()
{
	// A memory backend keeps the developer's real settings untouched while
	// still exercising the schema's types.
	var s = settings_for("preferences.reflog");

	s.set_int("commit-limit", 500);
	assert_cmpint(s.get_int("commit-limit"), CompareOperator.EQ, 500);

	var i = settings_for("preferences.interface");

	i.set_string("orientation", "horizontal");
	assert_cmpstr(i.get_string("orientation"), CompareOperator.EQ, "horizontal");
}

private static void test_orientation_is_an_enum()
{
	// Proving the key is the Layout enum rather than a plain string, by
	// reading the schema rather than by trying to set a bad value: GLib
	// treats an out-of-range enum value as a fatal warning, so probing it
	// would abort the test process rather than return false.
	var source = SettingsSchemaSource.get_default();
	var schema = source.lookup("%s.preferences.interface".printf(Gitrlz.Config.APPLICATION_ID),
	                           true);

	assert_nonnull(schema);

	var key = schema.get_key("orientation");
	var range = key.get_range();

	string type;
	Variant values;
	range.get("(sv)", out type, out values);

	assert_cmpstr(type, CompareOperator.EQ, "enum");

	var nicks = values.get_strv();
	assert_true("horizontal" in nicks);
	assert_true("vertical" in nicks);
}

public static int main(string[] args)
{
	// Never touch the user's real dconf database from a test.
	Environment.set_variable("GSETTINGS_BACKEND", "memory", true);

	Test.init(ref args);

	Test.add_func("/gitrlz/settings/interface-defaults", test_interface_defaults);
	Test.add_func("/gitrlz/settings/reflog-defaults", test_reflog_defaults);
	Test.add_func("/gitrlz/settings/window-state-defaults", test_window_state_defaults);
	Test.add_func("/gitrlz/settings/reflog-state-defaults", test_reflog_state_defaults);
	Test.add_func("/gitrlz/settings/values-round-trip", test_values_round_trip);
	Test.add_func("/gitrlz/settings/orientation-is-an-enum", test_orientation_is_an_enum);

	return Test.run();
}

}

// ex:set ts=4 noet:
