import utils;

import core.time : minutes;

//==============================================================================
// buildkite hook
//==============================================================================

@("answers-ping")
unittest
{
    setAPIExpectations();

    postBuildkiteHook("ping.json");
}

@("spawns-release-builder")
unittest
{
    setAPIExpectations(
        "/buildkite", &graphQL!("buildkite_organization", (ref Json j) {
            j.findPipeline("build-release")["scheduledBuilds"]["edges"] ~=
                ["node": ["branch": "master"]].serializeToJson;
        }),
        "/hcloud/servers"
    );

    postBuildkiteHook("build_scheduled_build-release.json");
}

@("reuse-running-release-builder")
unittest
{
    setAPIExpectations(
        "/buildkite", &graphQL!("buildkite_organization", (ref Json j) {
            j.findPipeline("build-release")["scheduledBuilds"]["edges"] ~=
                ["node": ["branch": "master"]].serializeToJson;
        }),
        "/hcloud/servers",
    );

    postBuildkiteHook("build_scheduled_build-release.json");
}

@("spawns-additional-release-builders")
unittest
{
    setAPIExpectations(
        "/buildkite", &graphQL!("buildkite_organization", (ref Json j) {
            j.findPipeline("build-release")["scheduledBuilds"]["edges"] ~=
                ["node": ["branch": "master"]].serializeToJson;
            j.findPipeline("build-release")["runningBuilds"]["edges"] ~=
                ["node": ["startedAt": (now - 30.minutes).toISOExtString]].serializeToJson;
        }),
        "/hcloud/servers",
    );

    postBuildkiteHook("build_scheduled_build-release.json");
}

@("reaps-dead-release-builders")
unittest
{
    setAPIExpectations(
        "/buildkite", &graphQL!("buildkite_organization", (ref Json j) {
            j.findPipeline("build-release")["scheduledBuilds"]["edges"] ~=
                ["node": ["branch": "master"]].serializeToJson;
            j.findAgents("release-builder-89cd08ef-e418-4b0f-9453-7a218662fbdb").front["node"]["connectionState"] = "lost";
        }),
        "/hcloud/servers",
    );

    postBuildkiteHook("build_scheduled_build-release.json");
}

//==============================================================================
// CI-Agents on Hetzner Cloud
//==============================================================================

Json hcloudCreateServerResp(ulong id, string name)
{
    import core.time : Duration;
    import std.datetime.timezone : SimpleTimeZone;
    import std.file : readText;
    import vibe.data.json : parseJsonString;

    // use zulu to get +00:00 instead of Z suffix
    static zulu = new immutable SimpleTimeZone(Duration.zero, "Etc/Zulu");
    auto time = now(zulu).toISOExtString;

    auto json = "data/payloads/hcloud_servers_post".readText.parseJsonString;
    json["server"]["id"] = id;
    json["server"]["name"] = name;
    json["server"]["created"] = time;
    json["action"]["started"] = time;
    return json;
}

// gets pipeline from buildkite GraphQL query for all pipelines
Json findPipeline(Json j, string name)
{
    return j["data"]["organization"]["pipelines"]["edges"][]
        .find!(p => p["node"]["name"] == name)[0]["node"];
}

@("spawns-ci-agent")
unittest
{
    setAPIExpectations(
        "/buildkite", &graphQL!("buildkite_organization", (ref Json j) {
            j.findPipeline("dmd")["scheduledBuilds"]["edges"] ~=
                ["node": ["branch": "master"]].serializeToJson;
        }),
        "/hcloud/servers", (ref Json j) {
            j["servers"] = Json.emptyArray;
        },
        "/hcloud/images?sort=created:desc&type=snapshot",
        "/hcloud/servers",
        (scope HTTPServerRequest req, scope HTTPServerResponse res) {
            assert(req.method == HTTPMethod.POST);
            auto name = req.json["name"].get!string;
            assert(name.startsWith("ci-agent-"));
            assert(req.json["image"] == "1461991");
            res.writeJsonBody(hcloudCreateServerResp(1321993, name));
        },
    );

    postBuildkiteHook("build_scheduled_dmd.json");
}

@("reuse-running-ci-agents")
unittest
{
    setAPIExpectations(
        "/buildkite", &graphQL!("buildkite_organization", (ref Json j) {
            j.findPipeline("dmd")["scheduledBuilds"]["edges"] ~=
                ["node": ["branch": "master"]].serializeToJson;
        }),
        "/hcloud/servers",
    );

    postBuildkiteHook("build_scheduled_dmd.json");
}

@("spawns-additional-ci-agents")
unittest
{
    setAPIExpectations(
        "/buildkite", &graphQL!("buildkite_organization", (ref Json j) {
            j.findPipeline("dmd")["scheduledBuilds"]["edges"] ~=
                ["node": ["branch": "master"]].serializeToJson;
            j.findPipeline("dmd")["scheduledBuilds"]["edges"] ~=
                ["node": ["branch": "master"]].serializeToJson;
            j.findPipeline("phobos")["scheduledBuilds"]["edges"] ~=
                ["node": ["branch": "MartinNowak:fix19337"]].serializeToJson;
        }),
        "/hcloud/servers",
        "/hcloud/images?sort=created:desc&type=snapshot",
        "/hcloud/servers",
        (scope HTTPServerRequest req, scope HTTPServerResponse res) {
            assert(req.method == HTTPMethod.POST);
            auto name = req.json["name"].get!string;
            assert(name.startsWith("ci-agent-"));
            assert(req.json["image"] == "1461991");
            res.writeJsonBody(hcloudCreateServerResp(1321994, name));
        },
    );

    postBuildkiteHook("build_scheduled_dmd.json");
}

@("reuses-existing-agent-from-running-builds")
unittest
{
    setAPIExpectations(
        "/buildkite", &graphQL!("buildkite_organization", (ref Json j) {
            j.findPipeline("dmd")["runningBuilds"]["edges"] ~=
                ["node": ["startedAt": (now - 10.minutes).toISOExtString]].serializeToJson;
            j.findPipeline("phobos")["runningBuilds"]["edges"] ~=
                ["node": ["startedAt": (now - 5.minutes).toISOExtString]].serializeToJson;
        }),
        "/hcloud/servers",
    );

    postBuildkiteHook("build_scheduled_dmd.json");
}

@("reaps-dead-ci-agents")
unittest
{
    setAPIExpectations(
        "/buildkite", &graphQL!"buildkite_organization",
        "/hcloud/servers", (ref Json j) {
            j["servers"][0]["status"] = "off";
            j["servers"][0]["id"] = 1321993;
            j["servers"][0]["name"] = "ci-agent-without-bk-agent";
            j["servers"][0]["created"] = (now - 30.minutes).toISOExtString;
        },
        "/hcloud/servers/1321993",
        (scope HTTPServerRequest req, scope HTTPServerResponse res) {
            assert(req.method == HTTPMethod.DELETE);
            res.writeBody("");
        },
        "/hcloud/images?sort=created:desc&type=snapshot",
        "/hcloud/servers",
        (scope HTTPServerRequest req, scope HTTPServerResponse res) {
            assert(req.method == HTTPMethod.POST);
            auto name = req.json["name"].get!string;
            assert(name.startsWith("ci-agent-"));
            assert(req.json["image"] == "1461991");
            res.writeJsonBody(hcloudCreateServerResp(1321994, name));
        },
    );

    postBuildkiteHook("build_scheduled_dmd.json");
}

//==============================================================================
// agent shutdown check
//==============================================================================

@("terminates-unneeded-release-builders")
unittest
{
    setAPIExpectations(
        "/buildkite", &graphQL!"buildkite_organization",
        "/hcloud/servers",
    );

    postAgentShutdownCheck("release-builder-123456");
}

@("terminates-unneeded-ci-agents")
unittest
{
    setAPIExpectations(
        "/buildkite", &graphQL!"buildkite_organization",
        "/hcloud/servers", (ref Json j) {
            j["servers"][0]["name"] = "ci-agent-123456";
            j["servers"][0]["id"] = 1321993;
        },
        "/hcloud/servers/1321993",
        (scope HTTPServerRequest req, scope HTTPServerResponse res) {
            assert(req.method == HTTPMethod.DELETE);
            res.writeBody("");
        }
    );

    postAgentShutdownCheck("ci-agent-123456");
}

@("keeps-needed-release-builders")
unittest
{
    setAPIExpectations(
        "/buildkite", &graphQL!("buildkite_organization", (ref Json j) {
            j.findPipeline("build-release")["runningBuilds"]["edges"] ~=
                ["node": ["startedAt": (now - 30.minutes).toISOExtString]].serializeToJson;
        }),
        "/hcloud/servers",
    );

    postAgentShutdownCheck("release-builder-123456");
}

@("keeps-needed-release-ci-agents")
unittest
{
    setAPIExpectations(
        "/buildkite", &graphQL!("buildkite_organization", (ref Json j) {
            j.findPipeline("dmd")["scheduledBuilds"]["edges"] ~=
                ["node": ["branch": "master"]].serializeToJson;
        }),
        "/hcloud/servers",
    );

    postAgentShutdownCheck("ci-agent-123456");
}

//==============================================================================
// dead server reaper
//==============================================================================

// gets agent from buildkite GraphQL query for all agents
auto findAgents(Json j, string hostname)
{
    return j["data"]["organization"]["agents"]["edges"][]
        .filter!(p => p["node"]["hostname"] == hostname);
}

@("reaps-dead-servers")
unittest
{
    import dlangbot.buildkite : cronReapDeadServers;

    setAPIExpectations(
        "/buildkite", &graphQL!("buildkite_organization", (ref Json j) {
            j.findAgents("ci-agent-88e9e60d-bfb0-4567-921e-c955eac25653").each!((ref j) { j["node"]["connectionState"] = "stopping"; });
            j.findAgents("release-builder-89cd08ef-e418-4b0f-9453-7a218662fbdb").front["node"]["connectionState"] = "lost";
        }),
        "/hcloud/servers", (ref Json j) {
            j["servers"][0]["id"] = 1321993;
            j["servers"][0]["name"] = "ci-agent-88e9e60d-bfb0-4567-921e-c955eac25653";
            j["servers"][0]["created"] = (now - 30.minutes).toISOExtString;
            j["servers"] ~= j["servers"][0].clone;
            j["servers"][1]["id"] = 1321994;
            j["servers"][1]["name"] = "ci-agent-93faf8ca-6633-4b96-9abb-3d9cb1c4018e";
            j["servers"][1]["created"] = (now - 40.minutes).toISOExtString;
        },
        "/hcloud/servers/1321993",
        (scope HTTPServerRequest req, scope HTTPServerResponse res) {
            assert(req.method == HTTPMethod.DELETE);
            res.writeBody("");
        },
    );

    cronReapDeadServers();
}

@("does-not-reap-running-servers")
unittest
{
    import dlangbot.buildkite : cronReapDeadServers;

    setAPIExpectations(
        "/buildkite", &graphQL!("buildkite_organization", (ref Json j) {
            // keep hosts running when some of it's agents are dead (might be due to updates or clean shutdown)
            j.findAgents("ci-agent-88e9e60d-bfb0-4567-921e-c955eac25653").front["node"]["connectionState"] = "stopping";
        }),
        "/hcloud/servers", (ref Json j) {
            j["servers"][0]["id"] = 1321993;
            j["servers"][0]["name"] = "ci-agent-88e9e60d-bfb0-4567-921e-c955eac25653";
            j["servers"][0]["created"] = (now - 30.minutes).toISOExtString;
            j["servers"] ~= j["servers"][0].clone;
            j["servers"][1]["id"] = 1321994;
            j["servers"][1]["name"] = "ci-agent-93faf8ca-6633-4b96-9abb-3d9cb1c4018e";
            j["servers"][1]["created"] = (now - 40.minutes).toISOExtString;
        },
    );

    cronReapDeadServers();
}
