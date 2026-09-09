defmodule Menard.RunTest do
  # The test verb's answer is the shit you care about (Andrew): counts, and per failure its name,
  # where, the assertion and its two sides — never a page of migration logs.
  use ExUnit.Case, async: true

  alias Menard.Run

  @out """
  18:53:59.922 [debug] QUERY OK source="event" db=0.2ms idle=0.0ms
  DELETE FROM "event" AS e0 []
  Running ExUnit with seed: 1, max_cases: 40

  ..

    1) test move/2 refuses another workspace (Server.ChannelsTest)
       test/server/channels_test.exs:40
       Assertion with == failed
       code:  assert moved.channel_id == infra.id
       left:  3
       right: 4
       stacktrace:
         test/server/channels_test.exs:44: (test)

    2) test deleting rehomes (Server.ChannelsTest)
       test/server/channels_test.exs:50
       ** (Exqlite.Error) FOREIGN KEY constraint failed
       DELETE FROM "workspace" AS w0
       stacktrace:
         (ecto_sql 3.14.0) lib/ecto/adapters/sql.ex:1121: Ecto.Adapters.SQL.raise_sql_call_error/1

  Finished in 0.5 seconds (0.1s async, 0.4s sync)
  Result: 3/5 passed
  Failed: 2 tests
  """

  test "parses counts and each failure's name, location, assertion and error" do
    r = Run.parse_test(@out, 2)
    assert r.tests == 5 and r.failed == 2 and r.ok == false

    assert [
             %{
               name: "move/2 refuses another workspace",
               module: "Server.ChannelsTest",
               at: "test/server/channels_test.exs:40",
               code: "assert moved.channel_id == infra.id",
               left: "3",
               right: "4"
             },
             %{
               name: "deleting rehomes",
               at: "test/server/channels_test.exs:50",
               error: "(Exqlite.Error) FOREIGN KEY constraint failed"
             }
           ] = Enum.map(r.failures, &Map.take(&1, [:name, :module, :at, :code, :left, :right, :error]))

    # the tail is the summary, not the logs
    assert r.tail == "Finished in 0.5 seconds (0.1s async, 0.4s sync)\nResult: 3/5 passed\nFailed: 2 tests"
  end

  # The test's own source, so the reader sees the assertion in context without opening the file.
  test "with_sources/2 attaches each failing test's body, read from the file under the root" do
    tmp = Path.join(System.tmp_dir!(), "menard-run-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(tmp, "test/server"))

    # the failure says line 40: pad so the test's `test` line IS line 40
    File.write!(
      Path.join(tmp, "test/server/channels_test.exs"),
      String.duplicate("\n", 38) <>
        "defmodule X do\n  test \"move/2 refuses another workspace\" do\n    assert moved.channel_id == infra.id\n  end\nend\n"
    )

    r = @out |> Run.parse_test(2) |> Run.with_sources(tmp)
    [first | _] = r.failures

    assert first.source ==
             "  test \"move/2 refuses another workspace\" do\n    assert moved.channel_id == infra.id\n  end"

    File.rm_rf!(tmp)
  end

  test "a green run has no failures and a one-line tail" do
    r = Run.parse_test("....\n\nFinished in 0.1 seconds (0.1s async, 0.0s sync)\nResult: 4 passed\n", 0)
    assert r.ok and r.tests == 4 and r.failed == 0 and r.failures == []
    assert r.tail == "Finished in 0.1 seconds (0.1s async, 0.0s sync)\nResult: 4 passed"
  end

  test "a test file that does not compile: the tail is the compiler's errors, not the stack trace" do
    out = """
    Compiling 1 file (.ex)
        error: undefined function thread/1 (expected Console.Panel.RailTest to define such a function)
        │
     79 │       rows = rows(thread(%{title: "build"}))
        │                   ^
        │
        └─ test/console/panel/rail_test.exs:79:19: Console.Panel.RailTest."test x"/1


    == Compilation error in file test/console/panel/rail_test.exs ==
    ** (CompileError) test/console/panel/rail_test.exs: cannot compile module Console.Panel.RailTest (errors have been logged)
        (elixir 1.20.4) lib/kernel/parallel_compiler.ex:667: Kernel.ParallelCompiler.require_file/2
        (elixir 1.20.4) lib/kernel/parallel_compiler.ex:550: anonymous fn/5 in Kernel.ParallelCompiler.spawn_workers/8
    """

    r = Run.parse_test(out, 1)
    refute r.ok
    assert r.tail =~ "error: undefined function thread/1"
    assert r.tail =~ "rail_test.exs:79:19"
    refute r.tail =~ "parallel_compiler"
  end
end
