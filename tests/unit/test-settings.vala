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

	assert_false(s.get_boolean("use-gravatar"));
	assert_true(s.get_boolean("enable-diff-highlighting"));
	assert_cmpstr(s.get_string("style-scheme"), CompareOperator.EQ, "classic");
}

private static void test_diff_defaults()
{
	var s = settings_for("preferences.diff");

	assert_false(s.get_boolean("ignore-whitespace"));
	assert_false(s.get_boolean("changes-inline"));
	assert_false(s.get_boolean("wrap"));
	assert_cmpint(s.get_int("context-lines"), CompareOperator.EQ, 3);
	assert_cmpint(s.get_int("tab-width"), CompareOperator.EQ, 4);
}

private static void test_commit_message_defaults()
{
	var s = settings_for("preferences.commit.message");

	assert_cmpstr(s.get_string("datetime-selection"), CompareOperator.EQ, "predefined");
	assert_cmpstr(s.get_string("predefined-datetime"), CompareOperator.EQ, "%Y-%m-%dT%R%z");
	assert_cmpstr(s.get_string("custom-datetime"), CompareOperator.EQ, "");
}

private static void test_diff_state_defaults()
{
	var s = settings_for("state.diff");

	assert_cmpstr(s.get_string("renderer"), CompareOperator.EQ, "split");
}

private static void test_preferences_lists_its_children()
{
	var source = SettingsSchemaSource.get_default();
	var schema = source.lookup("%s.preferences".printf(Gitrlz.Config.APPLICATION_ID),
	                           true);

	assert_nonnull(schema);

	var children = schema.list_children();

	assert_true("diff" in children);
	assert_true("interface" in children);
	assert_true("reflog" in children);
}

private static void test_reflog_defaults()
{
	var s = settings_for("preferences.reflog");

	assert_cmpint(s.get_int("collapse-inactive-lanes"), CompareOperator.EQ, 2);
	assert_true(s.get_boolean("collapse-inactive-lanes-enabled"));
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
	var s = settings_for("preferences.reflog");

	s.set_int("commit-limit", 500);
	assert_cmpint(s.get_int("commit-limit"), CompareOperator.EQ, 500);

	var i = settings_for("preferences.interface");

	i.set_string("orientation", "horizontal");
	assert_cmpstr(i.get_string("orientation"), CompareOperator.EQ, "horizontal");
}

private static void test_orientation_is_an_enum()
{
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
	Environment.set_variable("GSETTINGS_BACKEND", "memory", true);

	Test.init(ref args);

	Test.add_func("/gitrlz/settings/interface-defaults", test_interface_defaults);
	Test.add_func("/gitrlz/settings/diff-defaults", test_diff_defaults);
	Test.add_func("/gitrlz/settings/commit-message-defaults", test_commit_message_defaults);
	Test.add_func("/gitrlz/settings/reflog-defaults", test_reflog_defaults);
	Test.add_func("/gitrlz/settings/window-state-defaults", test_window_state_defaults);
	Test.add_func("/gitrlz/settings/diff-state-defaults", test_diff_state_defaults);
	Test.add_func("/gitrlz/settings/reflog-state-defaults", test_reflog_state_defaults);
	Test.add_func("/gitrlz/settings/preferences-lists-its-children", test_preferences_lists_its_children);
	Test.add_func("/gitrlz/settings/values-round-trip", test_values_round_trip);
	Test.add_func("/gitrlz/settings/orientation-is-an-enum", test_orientation_is_an_enum);

	return Test.run();
}

}
