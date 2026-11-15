# Pre-measurement audit schema correction

No measured block had started when this correction was recorded. The existing
collector has always launched the executable with its request-file path. The
first audit expected one argument, so it could not audit that valid output.
The corrected checker requires two arguments and verifies the exact request
path, executable, directory, and command digest.

The original declaration and recovery record are retained as `*.initial.json`;
the original auditor and exact patch are in `audit-amendment/`. The declaration's
original timestamp records when the source, fixtures, protocol and decision rules
were declared. Its amendment timestamp separately records this later audit-only
correction. The original qualification status retains its original declaration
and recovery hashes, and is checked against those preserved originals. The
qualification itself is not repeated. Subsequent measured-block statuses bind
the amended checker declaration and recovery record. Every listed experimental
parameter, source input, executable byte and decision threshold is identical.
