#!/usr/bin/env node

(function() {
    "use strict";

    if (process.argv.length != 3) {
        console.error("Usage: %s URI_TO_ENCODE", require("path").basename(__filename));
        process.exitCode = 1;
        return;
    }

    process.stdout.write(encodeURI(process.argv[2]).replace(/'/g, "%27"));
})();