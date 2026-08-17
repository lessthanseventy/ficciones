# agenix rules — which public keys each secret is encrypted to. `agenix -e <name>.age` reads THIS
# file (run from secrets/, or point RULES at it) to pick recipients, then encrypts the plaintext to
# them. The matching PRIVATE key on the box decrypts at home:switch (agenix identityPaths defaults to
# ~/.ssh/id_ed25519). Add a machine's pubkey here to let it decrypt; re-run `agenix -e` to re-encrypt.
#
# These are PUBLIC keys — safe to commit. The encrypted *.age files are also safe to commit; only the
# private key (never in this repo) can decrypt them.
let
  # This box — ~/.ssh/id_ed25519.pub.
  andrew = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH5nX7KoAVzS9v+ByfpGkk1A+mLV9L8d2PP9aZ9mZuyS andrew@lessthanseventy.com";

  # Every recipient that should be able to decrypt (add future machines here).
  all = [ andrew ];
in
{
  # The ollama.com API key — consumed non-interactively by the Tlön pi spawn (ollama-cloud/glm),
  # so it lives here rather than in rbw (which would need an interactive unlock). Create/rotate with
  # `agenix -e secrets/ollama-api-key.age` and paste ONLY the raw key (no trailing newline concerns —
  # mise reads the file verbatim).
  "ollama-api-key.age".publicKeys = all;
}
