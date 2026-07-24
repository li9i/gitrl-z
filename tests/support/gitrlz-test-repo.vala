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

/**
 * A scratch git repository driven by real git commands.
 *
 * Ported from tests/conftest.py's Repo class, which is the specification of
 * what the fixtures look like. Identity and dates are pinned so that hashes
 * and timestamps are deterministic: the visual regression suite (spec 6.3)
 * needs byte-identical repositories across runs, and the unit tests need to
 * assert on exact ISO dates.
 *
 * Test code may write to a repository. The application may not (spec NFR-4);
 * that asymmetry is deliberate and is why this helper shells out to git
 * rather than going through anything gitrl-z ships.
 */
public class Repo : Object
{
	public const string AUTHOR_DATE = "2026-07-20 10:00:00 +0200";
	public const string COMMITTER_DATE = "2026-07-20 11:00:00 +0200";

	public File path { get; private set; }

	private string[] d_env;

	public Repo(File location) throws Error
	{
		path = location;

		if (!location.query_exists())
		{
			location.make_directory_with_parents();
		}

		// Pinning the dates makes commit hashes reproducible. Pointing the
		// git config files at /dev/null keeps the developer's own git
		// configuration from leaking into a fixture.
		//
		// Built with Environ.set_variable rather than assembled by hand:
		// Process.spawn_sync's envp binding is declared null-terminated, and
		// an array built up in Vala is not. Environ.get() and
		// Environ.set_variable() both return proper NULL-terminated strv.
		var env = Environ.get();

		env = Environ.set_variable(env, "GIT_AUTHOR_DATE", AUTHOR_DATE, true);
		env = Environ.set_variable(env, "GIT_COMMITTER_DATE", COMMITTER_DATE, true);
		env = Environ.set_variable(env, "GIT_CONFIG_GLOBAL", "/dev/null", true);
		env = Environ.set_variable(env, "GIT_CONFIG_SYSTEM", "/dev/null", true);

		d_env = env;

		git({"init", "--quiet", "--initial-branch=main"});
		git({"config", "user.name", "Test Author"});
		git({"config", "user.email", "test@example.com"});
	}

	/**
	 * Create a repository in a fresh temporary directory.
	 *
	 * The caller owns the directory and should remove it; see remove().
	 */
	public static Repo create() throws Error
	{
		var dir = DirUtils.make_tmp("gitrlz-test-XXXXXX");
		return new Repo(File.new_for_path(dir));
	}

	public void branch(string name) throws Error
	{
		git({"branch", name});
	}

	public void checkout(string target) throws Error
	{
		git({"checkout", "--quiet", target});
	}

	/**
	 * Write a file, stage everything and commit. Returns the new sha.
	 */
	public string commit(string message = "commit", string? filename = null, string? content = null) throws Error
	{
		var name = filename != null ? filename : "file.txt";
		var body = content != null ? content : message + "\n";

		var target = path.get_child(name);
		var parent = target.get_parent();

		if (parent != null && !parent.query_exists())
		{
			parent.make_directory_with_parents();
		}

		FileUtils.set_contents(target.get_path(), body);

		git({"add", "--all"});
		git({"commit", "--quiet", "-m", message});

		return git({"rev-parse", "HEAD"}).strip();
	}

	/**
	 * Commit at a distinct date, for tests that need a realistic walk order.
	 *
	 * The other methods pin every date to one instant, which suits most
	 * assertions but gives the revision walker a degenerate order in which
	 * branches never sit as inactive lanes. A test that needs gitg's graph to
	 * interleave the way a real history does sets increasing dates through
	 * this. `day` is a whole-day offset from a fixed base, and it drives the
	 * committer date, which is what the walk sorts on.
	 */
	public string commit_at(int day, string message, string? filename = null) throws Error
	{
		var name = filename != null ? filename : "file.txt";
		FileUtils.set_contents(path.get_child(name).get_path(), message + "\n");

		git({"add", "--all"});

		var when = "@%lld".printf((int64)1577836800 + (int64)day * 86400);

		var env = Environ.set_variable(d_env, "GIT_AUTHOR_DATE", when, true);
		env = Environ.set_variable(env, "GIT_COMMITTER_DATE", when, true);

		run_git({"commit", "--quiet", "-m", message}, env);

		return git({"rev-parse", "HEAD"}).strip();
	}

	public void merge(string name, string message = "merge") throws Error
	{
		git({"merge", "--no-ff", "--quiet", "-m", message, name});
	}

	public void reset(string target) throws Error
	{
		git({"reset", "--quiet", "--hard", target});
	}

	/**
	 * Stash pending changes. The caller dirties the tree first.
	 */
	public void stash(string? message = null) throws Error
	{
		if (message != null)
		{
			git({"stash", "push", "--quiet", "--message", message});
		}
		else
		{
			git({"stash", "push", "--quiet"});
		}
	}

	/**
	 * Run git in this repository under the pinned environment.
	 */
	public string git(string[] args) throws Error
	{
		return run_git(args, d_env);
	}

	/**
	 * Run git under a caller-supplied environment.
	 */
	private string run_git(string[] args, string[] env) throws Error
	{
		// Null-terminated, for the same reason as the environment above.
		string[] argv = {};
		argv += "git";
		argv += "-C";
		argv += path.get_path();

		foreach (var arg in args)
		{
			argv += arg;
		}

		argv += null;

		string out;
		string err;
		int status;

		Process.spawn_sync(null,
		                   argv,
		                   env,
		                   SpawnFlags.SEARCH_PATH,
		                   null,
		                   out out,
		                   out err,
		                   out status);

		if (status != 0)
		{
			throw new IOError.FAILED("git %s failed: %s",
			                         string.joinv(" ", args),
			                         err.strip());
		}

		return out;
	}

	/**
	 * Recursively remove the repository directory.
	 */
	public void remove()
	{
		try
		{
			remove_recursive(path);
		}
		catch (Error e)
		{
			warning("could not remove fixture %s: %s", path.get_path(), e.message);
		}
	}

	private static void remove_recursive(File file) throws Error
	{
		var type = file.query_file_type(FileQueryInfoFlags.NOFOLLOW_SYMLINKS);

		if (type == FileType.DIRECTORY)
		{
			var children = file.enumerate_children("standard::name",
			                                       FileQueryInfoFlags.NOFOLLOW_SYMLINKS);

			FileInfo? info;

			while ((info = children.next_file()) != null)
			{
				remove_recursive(file.get_child(info.get_name()));
			}
		}

		file.delete();
	}
}

}

// ex:set ts=4 noet:
