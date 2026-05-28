/*
 * Transliteration of calculate_crc_bits.m (and the underlying
 * get_crc_generator_matrix.m construction) into a fixed-width C
 * function operating on bit arrays. The SAW driver in crc_3gpp.saw
 * proves this transliteration produces bit-identical output to the
 * Cryptol specification in crc_3gpp.cry for the four 3GPP CRC
 * polynomials at A = 16.
 *
 * Conventions match the rest of the codebase:
 *
 *   - Input `a` is an A-bit array, MSB-first, each entry 0 or 1.
 *   - Polynomial `poly` is a (P+1)-bit array, MSB-first, where index 0
 *     is the coefficient of x^P (the leading 1).
 *   - Output `out_p` is a P-bit array, MSB-first, holding the CRC bits.
 *
 * Algorithm (matches both calculate_crc_bits.m and the LFSR form):
 *
 *   1. Initialise a P-bit shift register `state` to all zero.
 *   2. For each of the A + P bits of `(a ++ zero_P)`: shift left by 1,
 *      pushing the incoming bit on the right; if the bit that fell off
 *      the high end was 1, XOR with `poly[1..P]`.
 *   3. The final `state` is the CRC.
 *
 * The function uses fixed-width arrays so SAW's `llvm_verify` can bind
 * to its symbolic interface without unrolling a variable loop bound.
 */

#include <stdint.h>
#include <stddef.h>

/*
 * Worker shared by all (A, P) instantiations. Takes the A input bits,
 * the (P+1)-bit polynomial, and writes P CRC bits to out_p. Sizes are
 * passed by parameter so the same body is reusable for the four 3GPP
 * polynomials.
 */
static void crc_calc(const uint8_t *a, size_t A,
                     const uint8_t *poly, size_t poly_len,
                     uint8_t *out_p)
{
    size_t P = poly_len - 1;
    uint8_t state[32];                  /* max P we use is 24 */
    for (size_t i = 0; i < P; i++) {
        state[i] = 0;
    }

    /* Process A real input bits, then P trailing zeros (the `*x^P` shift).
     * Mask each incoming byte to its LSB so the function's contract matches
     * the Cryptol spec: each input "bit" is the low bit of the byte. The
     * SAW proof in crc_3gpp.saw uses this masking so a byte-array of
     * arbitrary values still maps to a well-defined bit sequence. */
    for (size_t i = 0; i < A + P; i++) {
        uint8_t bit = (i < A) ? (a[i] & 1) : 0;
        uint8_t msb = state[0] & 1;
        for (size_t j = 0; j + 1 < P; j++) {
            state[j] = state[j + 1];
        }
        state[P - 1] = bit;
        if (msb) {
            for (size_t j = 0; j < P; j++) {
                state[j] ^= poly[j + 1];
            }
        }
    }

    for (size_t i = 0; i < P; i++) {
        out_p[i] = state[i];
    }
}

/* ----------------------------------------------------------------------
 * Polynomial constants (TS36.212 §5.1.1, MSB-first bit vectors).
 * ---------------------------------------------------------------------- */

static const uint8_t crc24A_poly[25] = {
    1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 1, 1, 1, 1, 0, 1, 1
};

static const uint8_t crc24B_poly[25] = {
    1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 1, 1
};

static const uint8_t crc16_poly[17] = {
    1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1
};

static const uint8_t crc8_poly[9] = {
    1, 1, 0, 0, 1, 1, 0, 1, 1
};

/* ----------------------------------------------------------------------
 * Polynomial- and length-specific entry points. Each calls crc_calc with
 * the right polynomial; SAW's llvm_verify binds each one separately
 * against its corresponding Cryptol counterpart.
 * ---------------------------------------------------------------------- */

void crc24A_A16(const uint8_t a[16], uint8_t out_p[24])
{
    crc_calc(a, 16, crc24A_poly, 25, out_p);
}

void crc24B_A16(const uint8_t a[16], uint8_t out_p[24])
{
    crc_calc(a, 16, crc24B_poly, 25, out_p);
}

void crc16_A16(const uint8_t a[16], uint8_t out_p[16])
{
    crc_calc(a, 16, crc16_poly, 17, out_p);
}

void crc8_A16(const uint8_t a[16], uint8_t out_p[8])
{
    crc_calc(a, 16, crc8_poly, 9, out_p);
}
