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

	public static Repo create() throws Error
	{
		var dir = DirUtils.make_tmp("gitrlz-test-XXXXXX");
		return new Repo(File.new_for_path(dir));
	}

	public void begin_operation(string marker) throws Error
	{
		var git_dir = path.get_child(".git");

		if (marker == "rebase")
		{
			git_dir.get_child("rebase-merge").make_directory();
			return;
		}

		FileUtils.set_contents(git_dir.get_child(marker).get_path(), "");
	}

	public void branch(string name) throws Error
	{
		git({"branch", name});
	}

	public void checkout(string target) throws Error
	{
		git({"checkout", "--quiet", target});
	}

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

	public string commit_bytes(string message, string filename, uint8[] content) throws Error
	{
		var target = path.get_child(filename);

		target.replace_contents(content, null, false, FileCreateFlags.REPLACE_DESTINATION,
		                        null, null);

		git({"add", "--all"});
		git({"commit", "--quiet", "-m", message});

		return git({"rev-parse", "HEAD"}).strip();
	}

	public void delete_branch(string name) throws Error
	{
		git({"branch", "-D", name});
	}

	public void merge(string name, string message = "merge") throws Error
	{
		git({"merge", "--no-ff", "--quiet", "-m", message, name});
	}

	public void reset(string target) throws Error
	{
		git({"reset", "--quiet", "--hard", target});
	}

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

	public string git(string[] args) throws Error
	{
		return run_git(args, d_env);
	}

	private string run_git(string[] args, string[] env) throws Error
	{
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
