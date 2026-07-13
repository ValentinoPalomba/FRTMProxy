import Foundation

enum DiffChange {
    case equal(String)
    case added(String)
    case removed(String)
}

enum LineDiff {
    static func compute(_ a: [String], _ b: [String]) -> [DiffChange] {
        let m = a.count, n = b.count
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...max(1, m) {
            for j in 1...max(1, n) {
                if i <= m, j <= n {
                    dp[i][j] = a[i - 1] == b[j - 1] ? dp[i - 1][j - 1] + 1 : max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var result: [DiffChange] = []
        var i = m, j = n
        while i > 0 || j > 0 {
            if i > 0, j > 0, a[i - 1] == b[j - 1] {
                result.append(.equal(a[i - 1]))
                i -= 1; j -= 1
            } else if j > 0, (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                result.append(.added(b[j - 1]))
                j -= 1
            } else if i > 0 {
                result.append(.removed(a[i - 1]))
                i -= 1
            } else {
                break
            }
        }
        return result.reversed()
    }
}
