module dlangbot.travis;

string travisAPIURL = "https://api.travis-ci.org";
string travisAuth;

import vibe.core.log;

//==============================================================================
// Dedup Travis-CI builds
//==============================================================================

void cancelBuild(size_t buildId)
{
    import std.format : format;
    import vibe.http.client : requestHTTP;
    import vibe.http.common : HTTPMethod;
    import vibe.stream.operations : readAllUTF8;

    auto url = "%s/builds/%s/cancel".format(travisAPIURL, buildId);
    requestHTTP(url, (scope req) {
        req.headers["Authorization"] = travisAuth;
        req.method = HTTPMethod.POST;
    }, (scope res) {
        if (res.statusCode / 100 == 2)
            logInfo("Canceled Build %s\n", buildId);
        else
            logWarn("POST %s failed;  %s %s.\n%s", url, res.statusPhrase,
                res.statusCode, res.bodyReader.readAllUTF8);
    });
}

void dedupTravisBuilds(string action, string repoSlug, uint pullRequestNumber)
{
    import std.algorithm.iteration : filter;
    import std.format : format;
    import std.range : drop;
    import vibe.http.client : requestHTTP;

    if (action != "synchronize" && action != "merged")
        return;

    static bool activeState(string state)
    {
        switch (state)
        {
        case "created", "queued", "started": return true;
        default: return false;
        }
    }

    auto url = "%s/repos/%s/builds?event_type=pull_request".format(travisAPIURL, repoSlug);
    auto activeBuildsForPR = requestHTTP(url, (scope req) {
            req.headers["Authorization"] = travisAuth;
            req.headers["Accept"] = "application/vnd.travis-ci.2+json";
        })
        .readJson["builds"][]
        .filter!(b => activeState(b["state"].get!string))
        .filter!(b => b["pull_request_number"].get!uint == pullRequestNumber);

    // Keep only the most recent build for this PR.  Kill all builds
    // when it got merged as it'll be retested after the merge anyhow.
    foreach (b; activeBuildsForPR.drop(action == "merged" ? 0 : 1))
        cancelBuild(b["id"].get!size_t);
}

