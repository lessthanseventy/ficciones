import { describe, expect, test } from "bun:test";
import { adapterForFile, findRootWith, ADAPTERS } from "./adapters.ts";

// The adapter registry is the pluggable seam — test that routing + root-finding are
// correct, so adding a language (a new adapter object) can't silently break the others.
// The LSP stdio client itself is integration (a real server), not unit-tested here.

describe("adapterForFile — route a file to its language server", () => {
  const cases: Array<[string, string | null]> = [
    ["/x/lib/foo.ex", "elixir"],
    ["/x/config/runtime.exs", "elixir"],
    ["/x/lib/foo_web/index.html.heex", "elixir"],
    ["/x/src/extension.ts", "typescript"],
    ["/x/src/component.tsx", "typescript"],
    ["/x/flake.nix", "nix"],
    ["/x/scripts/funes-cli.sh", "bash"],
    ["/x/package.json", "json"],
    ["/x/README.md", null], // markdown — no adapter (yet)
    ["/x/no-extension", null],
  ];
  for (const [file, name] of cases) {
    test(`${file} → ${name}`, () => {
      expect(adapterForFile(file)?.name ?? null).toBe(name);
    });
  }

  test("case-insensitive extension matching", () => {
    expect(adapterForFile("/x/Foo.EX")?.name).toBe("elixir");
    expect(adapterForFile("/x/Foo.TS")?.name).toBe("typescript");
  });
});

describe("findRootWith — walk up to a project marker", () => {
  test("mix.exs: finds the funes root from a deep lib file", () => {
    expect(findRootWith("/home/andrew/projects/ficciones/modules/funes/lib/funes/mcp/gateway.ex", "mix.exs")).toBe(
      "/home/andrew/projects/ficciones/modules/funes",
    );
  });
  test("tsconfig.json: finds the manos/consult root", () => {
    expect(findRootWith("/home/andrew/projects/ficciones/modules/manos/consult/src/extension.ts", "tsconfig.json")).toBe(
      "/home/andrew/projects/ficciones/modules/manos/consult",
    );
  });
  test("flake.nix: finds the repo root from flake.nix itself", () => {
    expect(findRootWith("/home/andrew/projects/ficciones/flake.nix", "flake.nix")).toBe(
      "/home/andrew/projects/ficciones",
    );
  });
  test("null when no marker is above the file", () => {
    expect(findRootWith("/tmp/orphan.ex", "mix.exs")).toBeNull();
  });
});

describe("ADAPTERS — every adapter declares a server + extensions + a root finder", () => {
  for (const a of ADAPTERS) {
    test(`${a.name}: has command, args, extensions, rootFor, serverPackage`, () => {
      expect(a.command.length).toBeGreaterThan(0);
      expect(Array.isArray(a.args)).toBe(true);
      expect(a.extensions.length).toBeGreaterThan(0);
      expect(typeof a.rootFor).toBe("function");
      expect(a.serverPackage.length).toBeGreaterThan(0);
    });
  }
});