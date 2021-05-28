import std.string;

import utils;

@("after-merge-close-issue-bugzilla")
unittest
{
    setAPIExpectations(
        "/github/repos/dlang/phobos/pulls/4963/commits", (ref Json j) {
            j[0]["commit"]["message"] = "Fix Issue 17564";
         },
        "/github/repos/dlang/phobos/issues/4963/comments",
        "/github/repos/dlang/phobos/issues/4963/labels",
        (scope HTTPServerRequest req, scope HTTPServerResponse res){
            res.writeJsonBody(Json.emptyArray);
        },
        "/github/repos/dlang/phobos/issues/4963/labels",
        (scope HTTPServerRequest req, scope HTTPServerResponse res){
            res.writeVoidBody;
        },
        "/trello/1/search?query=name:%22Issue%2017564%22&"~trelloAuth,
        "/bugzilla/buglist.cgi?bug_id=17564&ctype=csv&columnlist=short_desc,bug_status,resolution,bug_severity,priority,keywords",
        "/bugzilla/jsonrpc.cgi",
        (scope HTTPServerRequest req, scope HTTPServerResponse res){
            assert(req.json["method"].get!string == "Bug.comments");
            res.writeJsonBody([
                    "error" : Json(null),
                    "result" : [
                        "bugs" : [
                            "17564" : [
                                "comments" : Json.emptyArray
                            ].Json
                        ].Json
                    ].Json
                ].Json);
        },
        "/bugzilla/jsonrpc.cgi",
        (scope HTTPServerRequest req, scope HTTPServerResponse res){
            assert(req.method == HTTPMethod.POST);
            assert(req.json["method"].get!string == "Bug.update");
            assert(req.json["params"][0]["status"].get!string == "RESOLVED");
            assert(req.json["params"][0]["resolution"].get!string == "FIXED");

            auto comment = req.json["params"][0]["comment"]["body"].get!string;
            enum expected = q"EOF
dlang/phobos pull request #4963 "[DEMO for DIP1005] Converted imports to selective imports in std.array" was merged into master:

- e064d5664f92c4b2f0866c08f6d0290ba66825ed by Andrei Alexandrescu:
  Fix Issue 17564

https://github.com/dlang/phobos/pull/4963
EOF".chomp;
            assert(comment == expected, comment);

            auto j = Json(["error" : Json(null), "result" : Json.emptyObject]);
            res.writeJsonBody(j);
        },
    );

    postGitHubHook("dlang_phobos_merged_4963.json");
}

@("after-merge-comment-issue-bugzilla")
unittest
{
    setAPIExpectations(
        "/github/repos/dlang/phobos/pulls/4963/commits", (ref Json j) {
            j[0]["commit"]["message"] = "Do something with Issue 17564";
         },
        "/github/repos/dlang/phobos/issues/4963/comments",
        "/trello/1/search?query=name:%22Issue%2017564%22&"~trelloAuth,
        "/bugzilla/buglist.cgi?bug_id=17564&ctype=csv&columnlist=short_desc,bug_status,resolution,bug_severity,priority,keywords",
        "/bugzilla/jsonrpc.cgi",
        (scope HTTPServerRequest req, scope HTTPServerResponse res){
            assert(req.json["method"].get!string == "Bug.comments");
            res.writeJsonBody([
                    "error" : Json(null),
                    "result" : [
                        "bugs" : [
                            "17564" : [
                                "comments" : Json.emptyArray
                            ].Json
                        ].Json
                    ].Json
                ].Json);
        },
        "/bugzilla/jsonrpc.cgi",
        (scope HTTPServerRequest req, scope HTTPServerResponse res){
            assert(req.method == HTTPMethod.POST);
            assert(req.json["method"].get!string == "Bug.update");
            assert("status" !in req.json["params"][0]);
            assert("resolution" !in req.json["params"][0]);

            auto comment = req.json["params"][0]["comment"]["body"].get!string;
            enum expected = q"EOF
dlang/phobos pull request #4963 "[DEMO for DIP1005] Converted imports to selective imports in std.array" was merged into master:

- e064d5664f92c4b2f0866c08f6d0290ba66825ed by Andrei Alexandrescu:
  Do something with Issue 17564

https://github.com/dlang/phobos/pull/4963
EOF".chomp;
            assert(comment == expected, comment);

            auto j = Json(["error" : Json(null), "result" : Json.emptyObject]);
            res.writeJsonBody(j);
        },
    );

    postGitHubHook("dlang_phobos_merged_4963.json");
}

@("after-merge-dont-comment-other-org")
unittest
{
    setAPIExpectations(
        "/github/repos/notdlang/bar/pulls/12347/commits", (ref Json j) {
            j[0]["commit"]["message"] = "Do something with Issue 17564";
         },
        "/github/repos/notdlang/bar/issues/12347/comments",
    );

    postGitHubHook("notdlang_bar_merged_12347.json");
}

@("after-merge-dont-comment-non-bugzilla")
unittest
{
    setAPIExpectations(
        "/github/repos/dlang/dub/pulls/12345/commits", (ref Json j) {
            j[0]["commit"]["message"] = "Do something with Issue 17564";
         },
        "/github/repos/dlang/dub/issues/12345/comments",
    );

    postGitHubHook("dlang_dub_merged_12345.json");
}

@("after-merge-dont-spam-bugzilla")
unittest
{
    setAPIExpectations(
        "/github/repos/dlang/phobos/pulls/4963/commits", (ref Json j) {
            j[0]["commit"]["message"] = "Fix Issue 17564";
        },
        "/github/repos/dlang/phobos/issues/4963/comments",
        "/github/repos/dlang/phobos/issues/4963/labels",
        (scope HTTPServerRequest req, scope HTTPServerResponse res){
            res.writeJsonBody(Json.emptyArray);
        },
        "/github/repos/dlang/phobos/issues/4963/labels",
        (scope HTTPServerRequest req, scope HTTPServerResponse res){
            res.writeVoidBody;
        },
        "/trello/1/search?query=name:%22Issue%2017564%22&"~trelloAuth,
        "/bugzilla/buglist.cgi?bug_id=17564&ctype=csv&columnlist=short_desc,bug_status,resolution,bug_severity,priority,keywords",
        "/bugzilla/jsonrpc.cgi",
        (scope HTTPServerRequest req, scope HTTPServerResponse res){
            assert(req.json["method"].get!string == "Bug.comments");
            enum oldComment = q"EOF
dlang/phobos pull request #4963 "[DEMO for DIP1005] Converted imports to selective imports in std.array" was merged into stable:

- e064d5664f92c4b2f0866c08f6d0290ba66825ed by Andrei Alexandrescu:
  Fix Issue 17564

https://github.com/dlang/phobos/pull/4963
EOF".chomp;
            res.writeJsonBody([
                    "error" : Json(null),
                    "result" : [
                        "bugs" : [
                            "17564" : [
                                "comments" : [
                                    [
                                        "creator" : bugzillaLogin.Json,
                                        "text" : oldComment.Json
                                    ].Json,
                                ].Json,
                            ].Json
                        ].Json
                    ].Json
                ].Json);
        },
    );

    postGitHubHook("dlang_phobos_merged_4963.json");
}

@("pr-open-notify-bugzilla")
unittest
{
    setAPIExpectations(
        "/github/repos/dlang/dmd/pulls/6359/commits",
        "/github/repos/dlang/dmd/issues/6359/comments",
        "/bugzilla/buglist.cgi?bug_id=16794&ctype=csv&columnlist=short_desc,bug_status,resolution,bug_severity,priority,keywords",
        (scope HTTPServerRequest req, scope HTTPServerResponse res){
            res.writeBody(
`bug_id,"short_desc","bug_status","resolution","bug_severity","priority","keywords"
16794,"dmd not working on Ubuntu 16.10 because of default PIE linking","NEW","---","critical","P1",`);
        },
        "/github/orgs/dlang/public_members?per_page=100",
        "/github/repos/dlang/dmd/issues/6359/comments",
        "/github/repos/dlang/dmd/issues/6359/labels",
        "/github/repos/dlang/dmd/issues/6359/labels",
        (scope HTTPServerRequest req, scope HTTPServerResponse res) {},
        "/trello/1/search?query=name:%22Issue%2016794%22&"~trelloAuth,
        "/trello/1/cards/583f517a333add7c28e0cec7/actions?filter=commentCard&"~trelloAuth,
        "/trello/1/cards/583f517a333add7c28e0cec7/actions/583f517b91413ef81f1f9d34/comments?"~trelloAuth,
        (scope HTTPServerRequest req, scope HTTPServerResponse res) {},
        "/trello/1/cards/583f517a333add7c28e0cec7?"~trelloAuth,
        "/trello/1/board/55586bf9fd02d8c66074321a/lists?"~trelloAuth,
        "/trello/1/cards/583f517a333add7c28e0cec7/idList?value=55586d9b810fb97f9459df7d&"~trelloAuth,
        "/trello/1/cards/583f517a333add7c28e0cec7/pos?value=bottom&"~trelloAuth,
        "/bugzilla/jsonrpc.cgi", // Bug.comments
        "/bugzilla/jsonrpc.cgi", // Bug.update
        (scope HTTPServerRequest req, scope HTTPServerResponse res){
            assert(req.method == HTTPMethod.POST);
            assert(req.json["method"].get!string == "Bug.update");
            assert("status" !in req.json["params"][0]);
            assert("resolution" !in req.json["params"][0]);
            assert("keywords" in req.json["params"][0]);

            auto comment = req.json["params"][0]["comment"]["body"].get!string;
            auto expected = q"EOF
@MartinNowak created dlang/dmd pull request #6359 "fix Issue 16794 - dmd not working on Ubuntu 16.10" fixing this issue:

- fix Issue 16794 - dmd not working on Ubuntu 16.10
  
  - enable PIC by default on amd64 linux (no significant overhead, full
    PIC/PIE support)
  - also see https://github.com/dlang/installer/pull/207

https://github.com/dlang/dmd/pull/6359
EOF".chomp.replace("https://github.com/dlang/installer", githubURL ~ "/dlang/installer"); // compensate for API reference rewriting
            assert(comment == expected, comment);

            auto j = Json(["error" : Json(null), "result" : Json.emptyObject]);
            res.writeJsonBody(j);
        },
    );

    postGitHubHook("dlang_dmd_open_6359.json");
}

@("pr-open-notify-bugzilla-whitehole")
unittest
{
    setAPIExpectations(
        "/github/repos/dlang/dmd/pulls/6359/commits",
        (ref Json j){
            j[0]["commit"]["message"] = "Fix Issue 20540 - (White|Black)Hole does not work with return|scope functions";
        },
        "/github/repos/dlang/dmd/issues/6359/comments",
        "/bugzilla/buglist.cgi?bug_id=20540&ctype=csv&columnlist=short_desc,bug_status,resolution,bug_severity,priority,keywords",
        (scope HTTPServerRequest req, scope HTTPServerResponse res){
            res.writeBody(
`bug_id,"short_desc","bug_status","resolution","bug_severity","priority","keywords"
20540,"(White|Black)Hole does not work with return|scope functions","NEW","---","normal","P1","pull"`);
        },
        "/github/orgs/dlang/public_members?per_page=100",
        "/github/repos/dlang/dmd/issues/6359/comments",
        (scope HTTPServerRequest req, scope HTTPServerResponse res) {
            assert(req.method == HTTPMethod.POST);
            assert(req.json["body"].get!string.canFind(r"| \(White&#124;Black\)Hole does not work with return&#124;scope functions"));
        },
        "/github/repos/dlang/dmd/issues/6359/labels",
        "/github/repos/dlang/dmd/issues/6359/labels",
        (scope HTTPServerRequest req, scope HTTPServerResponse res) {},
        "/trello/1/search?query=name:%22Issue%2020540%22&"~trelloAuth,
        (scope HTTPServerRequest req, scope HTTPServerResponse res) {
            res.writeBody(`{"cards": []}`);
        },
        "/bugzilla/jsonrpc.cgi", // Bug.comments
        (scope HTTPServerRequest req, scope HTTPServerResponse res){
            res.writeBody(`{"error" : null, "result" : {
                "bugs" : {"20540" : {"comments" : []}},
                "comments" : {}
            }}`);
        },
        "/bugzilla/jsonrpc.cgi", // Bug.update
        (scope HTTPServerRequest req, scope HTTPServerResponse res){
            assert(req.method == HTTPMethod.POST);
            assert(req.json["method"].get!string == "Bug.update");

            auto j = Json(["error" : Json(null), "result" : Json.emptyObject]);
            res.writeJsonBody(j);
        },
    );

    postGitHubHook("dlang_dmd_open_6359.json");
}

@("pr-open-different-org")
unittest
{
    setAPIExpectations(
        "/github/repos/notdlang/foo/pulls/12346/commits",
        "/github/repos/notdlang/foo/issues/12346/comments",
    );

    postGitHubHook("notdlang_foo_open_12346.json");
}

@("pr-open-dont-spam-closed-bugzilla-issues")
unittest
{
    setAPIExpectations(
        "/github/repos/dlang/dmd/pulls/6359/commits",
        "/github/repos/dlang/dmd/issues/6359/comments",
        "/bugzilla/buglist.cgi?bug_id=16794&ctype=csv&columnlist=short_desc,bug_status,resolution,bug_severity,priority,keywords", // "RESOLVED"/"FIXED"
        "/github/orgs/dlang/public_members?per_page=100",
        "/github/repos/dlang/dmd/issues/6359/comments",
        "/github/repos/dlang/dmd/issues/6359/labels",
        "/github/repos/dlang/dmd/issues/6359/labels",
        (scope HTTPServerRequest req, scope HTTPServerResponse res) {},
        "/trello/1/search?query=name:%22Issue%2016794%22&"~trelloAuth,
        "/trello/1/cards/583f517a333add7c28e0cec7/actions?filter=commentCard&"~trelloAuth,
        "/trello/1/cards/583f517a333add7c28e0cec7/actions/583f517b91413ef81f1f9d34/comments?"~trelloAuth,
        (scope HTTPServerRequest req, scope HTTPServerResponse res) {},
        "/trello/1/cards/583f517a333add7c28e0cec7?"~trelloAuth,
        "/trello/1/board/55586bf9fd02d8c66074321a/lists?"~trelloAuth,
        "/trello/1/cards/583f517a333add7c28e0cec7/idList?value=55586d9b810fb97f9459df7d&"~trelloAuth,
        "/trello/1/cards/583f517a333add7c28e0cec7/pos?value=bottom&"~trelloAuth,
        "/bugzilla/jsonrpc.cgi", // Bug.comments
    );

    postGitHubHook("dlang_dmd_open_6359.json");
}

@("pr-synchronize-dont-spam")
unittest
{
    setAPIExpectations(
        "/github/repos/dlang/phobos/pulls/4921/commits",
        "/github/repos/dlang/phobos/issues/4921/labels",
        "/github/repos/dlang/phobos/issues/4921/comments",
        "/github/orgs/dlang/public_members?per_page=100",
        "/bugzilla/buglist.cgi?bug_id=8573&ctype=csv&columnlist=short_desc,bug_status,resolution,bug_severity,priority,keywords", // "NEW"/"---"
        "/github/repos/dlang/phobos/issues/comments/262784442",
        (scope HTTPServerRequest req, scope HTTPServerResponse res) {},
        "/trello/1/search?query=name:%22Issue%208573%22&"~trelloAuth,
        "/bugzilla/jsonrpc.cgi", // Bug.comments
        (scope HTTPServerRequest req, scope HTTPServerResponse res){
            assert(req.json["method"].get!string == "Bug.comments");
            enum oldComment = q"EOF
@andralex created dlang/phobos pull request #4921 "[DEMO for DIP1005] Converted imports to selective imports in std.array" mentioning this issue:

- yada yada

https://github.com/dlang/phobos/pull/4921
EOF".chomp;
            res.writeJsonBody([
                    "error" : Json(null),
                    "result" : [
                        "bugs" : [
                            "8573" : [
                                "comments" : [
                                    [
                                        "creator" : bugzillaLogin.Json,
                                        "text" : oldComment.Json
                                    ].Json,
                                ].Json,
                            ].Json
                        ].Json
                    ].Json
                ].Json);
        },
    );

    postGitHubHook("dlang_phobos_synchronize_4921.json");
}
