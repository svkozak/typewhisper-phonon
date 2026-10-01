#include "phonon_zstd.h"
#include "zstd.h"
#include <stdio.h>
#include <stdlib.h>

/* Streaming decoder: no external tools or writable executable downloads. */
int phonon_decompress(const char *source, const char *destination, uint64_t limit) {
    FILE *in = fopen(source, "rb"), *out = NULL;
    ZSTD_DStream *stream = NULL;
    void *input = NULL, *output = NULL;
    int result = -1;
    if (!in || !(out = fopen(destination, "wb")) || !(stream = ZSTD_createDStream())) goto cleanup;
    if (ZSTD_isError(ZSTD_initDStream(stream))) goto cleanup;
    if (ZSTD_isError(ZSTD_DCtx_setParameter(stream, ZSTD_d_windowLogMax, 27))) goto cleanup;
    size_t inputSize = ZSTD_DStreamInSize(), outputSize = ZSTD_DStreamOutSize(), remaining = 1;
    uint64_t total = 0;
    input = malloc(inputSize); output = malloc(outputSize);
    if (!input || !output) goto cleanup;
    size_t count;
    while ((count = fread(input, 1, inputSize, in)) > 0) {
        ZSTD_inBuffer src = { input, count, 0 };
        while (src.pos < src.size) {
            ZSTD_outBuffer dst = { output, outputSize, 0 };
            remaining = ZSTD_decompressStream(stream, &dst, &src);
            if (ZSTD_isError(remaining) || dst.pos > limit - total) goto cleanup;
            total += dst.pos;
            if (fwrite(output, 1, dst.pos, out) != dst.pos) goto cleanup;
        }
    }
    if (ferror(in) || remaining != 0 || fflush(out) != 0) goto cleanup;
    result = 0;
cleanup:
    free(input); free(output); ZSTD_freeDStream(stream);
    if (in) fclose(in);
    if (out && fclose(out) != 0) result = -1;
    if (result != 0) remove(destination);
    return result;
}
