.pragma library

var ALL_VIDEO_TARGETS = ["mp4", "mkv", "webm", "mov", "avi", "flv", "ts", "m4v"];
var ALL_AUDIO_TARGETS = ["mp3", "wav", "flac", "ogg", "m4a", "opus", "aac"];
var ALL_IMAGE_TARGETS = ["png", "jpg", "webp", "avif", "bmp", "ico", "tiff", "pdf"];
var ALL_DOC_TARGETS   = ["pdf", "docx", "odt", "md", "html", "epub", "rst", "txt"];

function targetsExcluding(list, selfExt) {
    var out = [];
    for (var i = 0; i < list.length; i++) {
        if (list[i] !== selfExt) out.push(list[i]);
    }
    return out;
}

var VIDEO_EXTS  = ["mp4", "mkv", "webm", "mov", "avi", "flv", "ts", "m4v"];
var AUDIO_EXTS  = ["mp3", "wav", "flac", "ogg", "m4a", "opus", "aac"];
var IMAGE_EXTS  = ["png", "jpg", "jpeg", "webp", "avif", "svg", "bmp", "ico", "tiff", "tif", "gif"];
var DOC_EXTS    = ["md", "html", "htm", "tex", "epub", "rst", "txt"];
var OFFICE_EXTS = ["doc", "docx", "odt", "xls", "xlsx", "ods", "ppt", "pptx", "odp", "csv"];

function getExtension(filePath) {
    if (!filePath) return "";
    var parts = filePath.split(".");
    return parts.length > 1 ? parts.pop().toLowerCase() : "";
}

function getTargets(ext) {
    var e = ext.toLowerCase();

    if (VIDEO_EXTS.indexOf(e) !== -1) {
        return targetsExcluding(ALL_VIDEO_TARGETS, e).concat(ALL_AUDIO_TARGETS, ["gif"]);
    }
    if (AUDIO_EXTS.indexOf(e) !== -1) {
        return targetsExcluding(ALL_AUDIO_TARGETS, e);
    }
    if (e === "gif") {
        return ALL_VIDEO_TARGETS.concat(targetsExcluding(ALL_IMAGE_TARGETS, "gif"));
    }
    if (IMAGE_EXTS.indexOf(e) !== -1) {
        var norm = (e === "jpeg") ? "jpg" : ((e === "tif") ? "tiff" : e);
        return targetsExcluding(ALL_IMAGE_TARGETS, norm).concat(["gif"]);
    }
    if (e === "pdf") {
        return ["png", "jpg", "webp", "tiff", "txt", "docx", "odt", "html", "md"];
    }
    if (e === "docx" || e === "doc" || e === "odt") {
        return targetsExcluding(ALL_DOC_TARGETS, e);
    }
    if (e === "xlsx" || e === "xls" || e === "ods" || e === "csv") {
        return targetsExcluding(["pdf", "xlsx", "ods", "csv", "html"], e);
    }
    if (e === "pptx" || e === "ppt" || e === "odp") {
        return targetsExcluding(["pdf", "pptx", "odp"], e);
    }
    if (DOC_EXTS.indexOf(e) !== -1) {
        var docNorm = (e === "htm") ? "html" : e;
        return targetsExcluding(ALL_DOC_TARGETS, docNorm);
    }

    return [];
}

function isMedia(ext) {
    var e = ext.toLowerCase();
    return VIDEO_EXTS.indexOf(e) !== -1 || AUDIO_EXTS.indexOf(e) !== -1 || e === "gif";
}

function normalizePath(raw) {
    if (!raw) return "";
    var p = raw.trim();
    if (p.indexOf("file://") === 0) {
        p = decodeURIComponent(p.substring(7));
    }
    return p;
}

function getPackageForEngine(engine) {
    var map = {
        "ffmpeg":    "ffmpeg",
        "magick":    "imagemagick",
        "pandoc":    "pandoc",
        "soffice":   "libreoffice-fresh",
        "pdftotext": "poppler",
        "pdftoppm":  "poppler"
    };
    return map[engine] || engine;
}

function estimateInitialSeconds(engine, fileBytes, mediaDurationSec, accelMode) {
    var mb = Math.max(0.1, fileBytes / (1024 * 1024));
    if (engine === "ffmpeg") {
        var factor = (accelMode === "nvenc" || accelMode === "vaapi") ? 0.08 : 0.25;
        if (mediaDurationSec > 0) return Math.max(1, Math.round(mediaDurationSec * factor));
        return Math.max(1, Math.round(mb * factor * 1.8));
    }
    if (engine === "soffice") return Math.max(3, Math.round(2.5 + mb * 0.6));
    if (engine === "magick" || engine === "pdftoppm") return Math.max(1, Math.round(0.8 + mb * 0.35));
    return Math.max(1, Math.round(0.6 + mb * 0.2));
}

function formatDuration(sec) {
    if (sec === null || sec === undefined || isNaN(sec) || sec < 0) return "--";
    var s = Math.ceil(sec);
    if (s < 60) return s + "s";
    var m = Math.floor(s / 60);
    var rem = s % 60;
    if (m < 60) return m + "m " + (rem < 10 ? "0" : "") + rem + "s";
    var h = Math.floor(m / 60);
    var remM = m % 60;
    return h + "h " + remM + "m";
}

// Resolves a guaranteed non-existing output path before invoking any tool
var UNIQUE_OUT_HELPER =
    "unique_out() { " +
    "  local base=\"$1\" ext=\"$2\" cand=\"${1}_converted.${2}\" n=1; " +
    "  while [ -e \"$cand\" ]; do cand=\"${base}_converted_${n}.${ext}\"; n=$((n + 1)); done; " +
    "  printf '%s' \"$cand\"; " +
    "}; ";

function wrapSafeCommand(basePath, dstExt, bodyScript, args) {
    var script = UNIQUE_OUT_HELPER + "OUT=$(unique_out \"$1\" \"$2\"); " + bodyScript;
    return ["bash", "-c", script, "bash", basePath, dstExt].concat(args);
}

function buildVideoFfmpegCmd(inputPath, basePath, dstExt, hwAccel, extraVf) {
    var isH264Container = (dstExt === "mp4" || dstExt === "mov" || dstExt === "mkv" || dstExt === "avi" || dstExt === "flv" || dstExt === "ts" || dstExt === "m4v");

    if (hwAccel === "nvenc" && isH264Container) {
        var vfPart = extraVf ? " -vf " + extraVf : "";
        var acodec = (dstExt === "avi") ? "mp3" : "aac";
        return {
            engine: "ffmpeg",
            accel: "GPU (NVENC)",
            outPath: basePath + "_converted." + dstExt,
            cmd: wrapSafeCommand(
                basePath,
                dstExt,
                "ffmpeg -n -progress pipe:1 -nostats -i \"$3\"" + vfPart + " -c:v h264_nvenc -preset p4 -cq 23 -c:a " + acodec + " -b:a 192k \"$OUT\" && printf '\\n__OUT_PATH__=%s\\n' \"$OUT\"",
                [inputPath]
            )
        };
    }

    if (hwAccel === "vaapi" && (isH264Container || dstExt === "webm")) {
        var vaCodec = dstExt === "webm" ? "vp9_vaapi" : "h264_vaapi";
        var vaFilter = extraVf ? (extraVf + ",format=nv12,hwupload") : "format=nv12,hwupload";
        var vaAcodec = dstExt === "webm" ? "libopus" : (dstExt === "avi" ? "mp3" : "aac");
        return {
            engine: "ffmpeg",
            accel: "GPU (VAAPI)",
            outPath: basePath + "_converted." + dstExt,
            cmd: wrapSafeCommand(
                basePath,
                dstExt,
                "ffmpeg -n -progress pipe:1 -nostats -vaapi_device /dev/dri/renderD128 -i \"$3\" -vf \"" + vaFilter + "\" -c:v " + vaCodec + " -c:a " + vaAcodec + " \"$OUT\" && printf '\\n__OUT_PATH__=%s\\n' \"$OUT\"",
                [inputPath]
            )
        };
    }

    var cpuVfPart = extraVf ? " -vf \"" + extraVf + "\"" : "";
    return {
        engine: "ffmpeg",
        accel: "CPU",
        outPath: basePath + "_converted." + dstExt,
        cmd: wrapSafeCommand(
            basePath,
            dstExt,
            "ffmpeg -n -progress pipe:1 -nostats -i \"$3\"" + cpuVfPart + " \"$OUT\" && printf '\\n__OUT_PATH__=%s\\n' \"$OUT\"",
            [inputPath]
        )
    };
}

function buildSofficeCmd(inputPath, basePath, dstExt, inFilter) {
    var filterArg = inFilter ? ("--infilter=" + inFilter + " ") : "";
    return {
        engine: "soffice",
        accel: "CPU",
        outPath: basePath + "_converted." + dstExt,
        cmd: wrapSafeCommand(
            basePath,
            dstExt,
            "TMPD=$(mktemp -d) || exit 1; trap 'rm -rf \"$TMPD\"' EXIT; " +
            "soffice --headless " + filterArg + "--convert-to \"$2\" --outdir \"$TMPD\" \"$3\" >/dev/null && " +
            "GEN=$(find \"$TMPD\" -maxdepth 1 -type f | head -n 1) && [ -n \"$GEN\" ] && " +
            "mv -n \"$GEN\" \"$OUT\" && printf '\\n__OUT_PATH__=%s\\n' \"$OUT\"",
            [inputPath]
        )
    };
}

function buildCommand(inputPath, targetExt, hwAccel) {
    var srcExt = getExtension(inputPath);
    var dstExt = targetExt.toLowerCase();
    var dotIdx = inputPath.lastIndexOf(".");
    var slashIdx = inputPath.lastIndexOf("/");
    var basePath = dotIdx > slashIdx ? inputPath.substring(0, dotIdx) : inputPath;
    var defaultOutPath = basePath + "_converted." + dstExt;

    // 1. PDF input
    if (srcExt === "pdf") {
        if (dstExt === "txt") {
            return {
                engine: "pdftotext",
                accel: "CPU",
                outPath: defaultOutPath,
                cmd: wrapSafeCommand(basePath, dstExt, "pdftotext \"$3\" \"$OUT\" && printf '\\n__OUT_PATH__=%s\\n' \"$OUT\"", [inputPath])
            };
        }
        if (dstExt === "md") {
            return {
                engine: "pandoc",
                accel: "CPU",
                outPath: defaultOutPath,
                cmd: wrapSafeCommand(
                    basePath,
                    dstExt,
                    "TMPD=$(mktemp -d) || exit 1; trap 'rm -rf \"$TMPD\"' EXIT; " +
                    "soffice --headless --infilter=writer_pdf_import --convert-to html --outdir \"$TMPD\" \"$3\" >/dev/null && " +
                    "HTMLF=$(find \"$TMPD\" -maxdepth 1 -type f -name '*.html' | head -n 1) && [ -n \"$HTMLF\" ] && " +
                    "pandoc --sandbox \"$HTMLF\" -t gfm -o \"$OUT\" && printf '\\n__OUT_PATH__=%s\\n' \"$OUT\"",
                    [inputPath]
                )
            };
        }
        if (["png", "jpg", "webp", "tiff"].indexOf(dstExt) !== -1) {
            var ppmFlag = (dstExt === "jpg") ? "jpeg" : dstExt;
            return {
                engine: "pdftoppm",
                accel: "CPU",
                outPath: defaultOutPath,
                cmd: wrapSafeCommand(
                    basePath,
                    dstExt,
                    "if command -v pdftoppm >/dev/null 2>&1; then " +
                    "  pdftoppm -" + ppmFlag + " -r 150 -singlefile \"$3\" \"${OUT%.*}\" 2>/dev/null || magick -density 150 \"$3\" \"$OUT\"; " +
                    "else magick -density 150 \"$3\" \"$OUT\"; fi && printf '\\n__OUT_PATH__=%s\\n' \"$OUT\"",
                    [inputPath]
                )
            };
        }
        return buildSofficeCmd(inputPath, basePath, dstExt, "writer_pdf_import");
    }

    // 2. GIF -> Video or Still Image
    if (srcExt === "gif") {
        if (VIDEO_EXTS.indexOf(dstExt) !== -1) {
            return buildVideoFfmpegCmd(inputPath, basePath, dstExt, hwAccel || "cpu", "scale=trunc(iw/2)*2:trunc(ih/2)*2,pix_fmt=yuv420p");
        }
        return {
            engine: "magick",
            accel: "CPU",
            outPath: defaultOutPath,
            cmd: wrapSafeCommand(basePath, dstExt, "magick \"${3}[0]\" \"$OUT\" && printf '\\n__OUT_PATH__=%s\\n' \"$OUT\"", [inputPath])
        };
    }

    // 3. Video -> Video / Audio / GIF
    if (VIDEO_EXTS.indexOf(srcExt) !== -1) {
        if (VIDEO_EXTS.indexOf(dstExt) !== -1) {
            return buildVideoFfmpegCmd(inputPath, basePath, dstExt, hwAccel || "cpu", null);
        }
        if (dstExt === "gif") {
            return {
                engine: "ffmpeg",
                accel: "CPU",
                outPath: defaultOutPath,
                cmd: wrapSafeCommand(
                    basePath,
                    dstExt,
                    "ffmpeg -n -progress pipe:1 -nostats -i \"$3\" -vf \"fps=15,scale=640:-1:flags=lanczos\" \"$OUT\" && printf '\\n__OUT_PATH__=%s\\n' \"$OUT\"",
                    [inputPath]
                )
            };
        }
        return {
            engine: "ffmpeg",
            accel: "CPU",
            outPath: defaultOutPath,
            cmd: wrapSafeCommand(
                basePath,
                dstExt,
                "ffmpeg -n -progress pipe:1 -nostats -i \"$3\" -vn \"$OUT\" && printf '\\n__OUT_PATH__=%s\\n' \"$OUT\"",
                [inputPath]
            )
        };
    }

    // 4. Audio -> Audio
    if (AUDIO_EXTS.indexOf(srcExt) !== -1) {
        return {
            engine: "ffmpeg",
            accel: "CPU",
            outPath: defaultOutPath,
            cmd: wrapSafeCommand(
                basePath,
                dstExt,
                "ffmpeg -n -progress pipe:1 -nostats -i \"$3\" \"$OUT\" && printf '\\n__OUT_PATH__=%s\\n' \"$OUT\"",
                [inputPath]
            )
        };
    }

    // 5. Images -> ImageMagick
    if (IMAGE_EXTS.indexOf(srcExt) !== -1) {
        return {
            engine: "magick",
            accel: "CPU",
            outPath: defaultOutPath,
            cmd: wrapSafeCommand(basePath, dstExt, "magick \"$3\" \"$OUT\" && printf '\\n__OUT_PATH__=%s\\n' \"$OUT\"", [inputPath])
        };
    }

    // 6. Office formats
    if (OFFICE_EXTS.indexOf(srcExt) !== -1) {
        if ((srcExt === "docx" || srcExt === "odt") && (dstExt === "md" || dstExt === "html" || dstExt === "txt" || dstExt === "epub" || dstExt === "rst")) {
            var pandocFmt = (dstExt === "txt") ? "plain" : ((dstExt === "md") ? "gfm" : dstExt);
            return {
                engine: "pandoc",
                accel: "CPU",
                outPath: defaultOutPath,
                cmd: wrapSafeCommand(
                    basePath,
                    dstExt,
                    "pandoc --sandbox \"$3\" -t " + pandocFmt + " -o \"$OUT\" && printf '\\n__OUT_PATH__=%s\\n' \"$OUT\"",
                    [inputPath]
                )
            };
        }
        return buildSofficeCmd(inputPath, basePath, dstExt, null);
    }

    // 7. Plain Text (.txt) input
    if (srcExt === "txt") {
        if (dstExt === "pdf" || dstExt === "docx" || dstExt === "odt") {
            return buildSofficeCmd(inputPath, basePath, dstExt, null);
        }
        var txtTargetFmt = (dstExt === "md") ? "gfm" : dstExt;
        return {
            engine: "pandoc",
            accel: "CPU",
            outPath: defaultOutPath,
            cmd: wrapSafeCommand(
                basePath,
                dstExt,
                "pandoc --sandbox -f markdown \"$3\" -t " + txtTargetFmt + " -o \"$OUT\" && printf '\\n__OUT_PATH__=%s\\n' \"$OUT\"",
                [inputPath]
            )
        };
    }

    // 8. Markup & Documents (md, html, tex, epub, rst)
    if (dstExt === "pdf") {
        return {
            engine: "pandoc",
            accel: "CPU",
            outPath: defaultOutPath,
            cmd: wrapSafeCommand(
                basePath,
                dstExt,
                "TMPD=$(mktemp -d) || exit 1; trap 'rm -rf \"$TMPD\"' EXIT; " +
                "if pandoc --sandbox \"$3\" -o \"$TMPD/out.pdf\" 2>/dev/null; then " +
                "  mv -n \"$TMPD/out.pdf\" \"$OUT\"; " +
                "else " +
                "  pandoc --sandbox \"$3\" -o \"$TMPD/doc.html\" && " +
                "  soffice --headless --convert-to pdf --outdir \"$TMPD\" \"$TMPD/doc.html\" >/dev/null && " +
                "  mv -n \"$TMPD/doc.pdf\" \"$OUT\"; " +
                "fi && printf '\\n__OUT_PATH__=%s\\n' \"$OUT\"",
                [inputPath]
            )
        };
    }
    if (dstExt === "txt") {
        return {
            engine: "pandoc",
            accel: "CPU",
            outPath: defaultOutPath,
            cmd: wrapSafeCommand(
                basePath,
                dstExt,
                "pandoc --sandbox \"$3\" -t plain -o \"$OUT\" && printf '\\n__OUT_PATH__=%s\\n' \"$OUT\"",
                [inputPath]
            )
        };
    }
    return {
        engine: "pandoc",
        accel: "CPU",
        outPath: defaultOutPath,
        cmd: wrapSafeCommand(
            basePath,
            dstExt,
            "pandoc --sandbox \"$3\" -o \"$OUT\" && printf '\\n__OUT_PATH__=%s\\n' \"$OUT\"",
            [inputPath]
        )
    };
}
