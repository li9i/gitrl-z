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

namespace Gitrlz
{

public int main(string[] args)
{
	Intl.setlocale(LocaleCategory.ALL, "");
	Intl.bindtextdomain(Config.GETTEXT_PACKAGE, Config.GITG_LOCALEDIR);
	Intl.bind_textdomain_codeset(Config.GETTEXT_PACKAGE, "UTF-8");
	Intl.textdomain(Config.GETTEXT_PACKAGE);

	// No code here can need a display. Application.local_command_line
	// processes --version, --help and the not-a-repository error before
	// GApplication opens a display (spec FR-104).
	var app = new Gitrlz.Application();

	return app.run(args);
}

}

// ex:set ts=4 noet:
