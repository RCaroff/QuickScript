#!/usr/bin/env php
<?php
//
// Test PHP — vérifie que QuickScript exécute correctement les scripts
// .php via php, et expose les variables QS_CONTEXT_*.
//
// ⚠ LIMITATION : ScriptHeaderParser s'arrête au premier `<?php` (ce n'est ni
//   un commentaire `#`/`//` ni un shebang), donc les `@param` placés
//   après `<?php` ne sont PAS détectés et aucun dialog QuickScript ne
//   sera proposé pour ce script. Lance-le sans paramètres : le script se
//   contente de saluer "world" par défaut.
//
$args = array_slice($argv, 1);
$name = $args[0] ?? "world";

echo "Hello, {$name}!  (php " . PHP_VERSION . ")\n";
echo "argv         : " . json_encode($args) . "\n";
echo "QS_FILE_PATH : " . (getenv("QS_CONTEXT_FILE_PATH") ?: "(unset)") . "\n";
echo "QS_TARGET    : " . (getenv("QS_CONTEXT_TARGET_PATH") ?: "(unset)") . "\n";
