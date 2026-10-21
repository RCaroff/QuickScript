#!/usr/bin/env php
<?php
//
// PHP test — checks that QuickScript correctly runs .php scripts via php,
// and exposes the QS_CONTEXT_* variables.
//
// ⚠ LIMITATION: ScriptHeaderParser stops at the first `<?php` (it is neither
//   a `#`/`//` comment nor a shebang), so `@param` lines placed after
//   `<?php` are NOT detected and QuickScript shows no dialog for this
//   script. Run it without parameters: it simply greets "world".
//
$args = array_slice($argv, 1);
$name = $args[0] ?? "world";

echo "Hello, {$name}!  (php " . PHP_VERSION . ")\n";
echo "argv         : " . json_encode($args) . "\n";
echo "QS_FILE_PATH : " . (getenv("QS_CONTEXT_FILE_PATH") ?: "(unset)") . "\n";
echo "QS_TARGET    : " . (getenv("QS_CONTEXT_TARGET_PATH") ?: "(unset)") . "\n";
