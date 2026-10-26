#!/usr/bin/awk -f
# check.awk -v status=<depsort exit> pairs.txt report.txt
# Independent verifier. Prints "" if the report is a correct answer for pairs.txt
# (either a valid build order or a genuine cycle), otherwise a failure reason.
BEGIN { bad = "" }

FNR == 1 { file++ }                       # file 1 = pairs, file 2 = report
file == 1 {
    if (NF == 0) next
    if (NF != 2) { bad = "malformed pair line " FNR; exit }
    a = $1; b = $2
    if (!(a in pkg)) { pkg[a] = 1; npkg++ }
    if (!(b in pkg)) { pkg[b] = 1; npkg++ }
    k = a SUBSEP b
    if (!(k in ed)) { ed[k] = 1; nedges++; ea[nedges] = a; eb[nedges] = b }
    next
}
file == 2 {
    if (NF == 0) next
    rep[++nrep] = $0
}

END {
    if (bad != "") { print bad; exit }
    if (npkg == 0) {                      # empty input
        if (status != 0) { print "empty input but exit " status; exit }
        if (nrep != 0) { print "empty input but output"; exit }
        exit
    }
    if (status == 2 || (status != 0 && status != 1)) {
        print "unexpected exit status " status; exit
    }

    if (status == 0) {
        # must be a permutation of the packages, and every edge respected
        for (i = 1; i <= nrep; i++) {
            if (rep[i] ~ / /) { print "order line " i " has a space: " rep[i]; exit }
            if (rep[i] in pos) { print "duplicate in order: " rep[i]; exit }
            pos[rep[i]] = i
        }
        if (nrep != npkg) {
            print "order has " nrep " lines, expected " npkg " packages"; exit
        }
        for (p in pkg) if (!(p in pos)) { print "missing package: " p; exit }
        for (i = 1; i <= nedges; i++) {
            a = ea[i]; b = eb[i]
            if (!(pos[b] < pos[a])) {
                print "edge " a "->" b " violated (" b "=" pos[b] ", " a "=" pos[a] ")"; exit
            }
        }
        exit
    }

    # status == 1: must be a genuine, closed cycle over real edges
    if (nrep != 1) { print "cycle answer must be exactly one line, got " nrep; exit }
    if (rep[1] !~ /^cycle: /) { print "bad cycle prefix: " rep[1]; exit }
    line = substr(rep[1], 8)
    n = split(line, c, " ")
    if (n < 2) { print "cycle line too short: " rep[1]; exit }
    if (c[1] != c[n]) { print "cycle not closed: " rep[1]; exit }
    for (i = 1; i < n; i++) {
        if (!(c[i] in pkg)) { print "cycle names unknown package: " c[i]; exit }
        k = c[i + 1] SUBSEP c[i]          # "a needs b": edge a->b
        if (!(k in ed)) { print "cycle uses edge that does not exist: " c[i + 1] " " c[i]; exit }
    }
}
