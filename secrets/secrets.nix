# agenix rules: which public keys each secret is encrypted to (agenix -e <name>.age reads this
# file). Decrypted at home:switch with the matching private key (identityPaths defaults to
# ~/.ssh/id_ed25519). These are PUBLIC keys, safe to commit; so are the *.age files.
let
  # This box — ~/.ssh/id_ed25519.pub.
  andrew = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH5nX7KoAVzS9v+ByfpGkk1A+mLV9L8d2PP9aZ9mZuyS andrew@lessthanseventy.com";

  # Every recipient that should be able to decrypt (add future machines here).
  all = [ andrew ];
in
{
  # ollama.com API key — consumed non-interactively by the Tlön pi spawn, so it lives here rather
  # than rbw (needs interactive unlock). Rotate with `agenix -e secrets/ollama-api-key.age`.
  "ollama-api-key.age".publicKeys = all;
}
