#!/usr/bin/env python3
"""Exercise the actual native C ABI from Python ctypes, with no Solvent document."""
import ctypes as C
import json
from pathlib import Path
import sys


def main():
    if len(sys.argv) > 1:
        path = Path(sys.argv[1])
    else:
        matches = list((Path(__file__).parent / "target/release").rglob("libgcs.so"))
        if len(matches) != 1:
            raise RuntimeError(f"Expected one libgcs.so after --features abi-probe build, found {len(matches)}; pass an exact path")
        path = matches[0]
    lib = C.CDLL(str(path.resolve()))
    ptr = C.c_void_p
    number = C.c_double
    nbuf = C.POINTER(number)
    signatures = {
        "gcs_sketch_new": (ptr, []),
        "gcs_sketch_free": (None, [ptr]),
        "gcs_sketch_point": (C.c_int32, [ptr, number, number, C.c_int32, C.c_char_p, C.c_size_t]),
        "gcs_sketch_line": (C.c_int32, [ptr, C.c_int32, C.c_int32]),
        "gcs_constraint_add": (C.c_int32, [ptr, C.c_char_p, C.c_size_t]),
        "gcs_solve": (ptr, [ptr, C.c_int32, number, C.c_int32, C.c_int32, C.c_int32, nbuf]),
        "gcs_sketch_get_x": (None, [ptr, nbuf]),
        "gcs_diagnose_json": (ptr, [ptr, C.c_char_p, C.c_size_t]),
        "gcs_str_len": (C.c_uint32, [ptr]),
        "gcs_str_ptr": (ptr, [ptr]),
        "gcs_str_free": (None, [ptr]),
        "gcs_last_error": (ptr, []),
    }
    for name, (ret, args) in signatures.items():
        fn = getattr(lib, name)
        fn.restype, fn.argtypes = ret, args

    def take(p):
        if not p:
            return ""
        try:
            return C.string_at(lib.gcs_str_ptr(p), lib.gcs_str_len(p)).decode("utf8")
        finally:
            lib.gcs_str_free(p)

    sketch = lib.gcs_sketch_new()
    if not sketch:
        raise RuntimeError(take(lib.gcs_last_error()))
    try:
        a = lib.gcs_sketch_point(sketch, 0, 0, 1, b"a", 1)
        b = lib.gcs_sketch_point(sketch, 25, 3, 0, b"b", 1)
        c = lib.gcs_sketch_point(sketch, 2, 33, 0, b"c", 1)
        ab = lib.gcs_sketch_line(sketch, a, b)
        ac = lib.gcs_sketch_line(sketch, a, c)
        records = [
            {"type": "Horizontal", "args": [["line", ab]]},
            {"type": "Perpendicular", "args": [["line", ab], ["line", ac]]},
            {"type": "Distance", "args": [["point", a], ["point", b], 30]},
            {"type": "Distance", "args": [["point", a], ["point", c], 40]},
        ]
        ids = []
        for record in records:
            payload = json.dumps(record, separators=(",", ":")).encode()
            cid = lib.gcs_constraint_add(sketch, payload, len(payload))
            if cid < 0:
                raise RuntimeError(take(lib.gcs_last_error()))
            ids.append(cid)
        result = (number * 9)()
        message = take(lib.gcs_solve(sketch, 0, 1e-14, 100, 1000, -1, result))
        coords = (number * 6)()
        lib.gcs_sketch_get_x(sketch, coords)
        diag = json.loads(take(lib.gcs_diagnose_json(sketch, b"{}", 2)))
        expected = [0, 0, 30, 0, 0, 40]
        error = max(abs(x - y) for x, y in zip(coords, expected))
        passed = result[0] == 1 and error < 1e-7 and diag.get("dof") == 0
        row = {
            "probe": "native_c_abi_without_language",
            "passed": passed,
            "upstream_revision": "64bad08b2f126f6be495f6647c180ae703e0963e",
            "host": "Python ctypes calling exported symbols in libgcs.so",
            "constraint_ids": ids,
            "reported_success": result[0] == 1,
            "status_message": message,
            "coordinates": list(coords),
            "max_coordinate_error": error,
            "diagnostic_dof": diag.get("dof"),
            "document_text_supplied": False,
        }
        print(json.dumps(row, allow_nan=False, separators=(",", ":")))
        return 0 if passed else 1
    finally:
        lib.gcs_sketch_free(sketch)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(json.dumps({"probe": "native_c_abi_without_language", "passed": False, "error": str(exc)}))
        raise SystemExit(1)
