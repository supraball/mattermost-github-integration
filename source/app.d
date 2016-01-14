module app;

import vibe.d;
import vibe.data.json;
import std.stdio;


struct Config
{
    struct Mapping
    {
        string channel;
        string repo;
        @optional string user;
        @optional string icon;
    }

    @optional ushort port = 9585;
    @optional string key; // unused

    @optional string user; // default mattermost user
    @optional string channel; // default mattermost channel
    @optional string icon; // default icon

    string mattermost_hook; // webhook url

    @optional Mapping[] mappings; // repo specific config
}

Config config;

shared static this ( )
{
    import vibe.core.file;
    auto config_string = readFile("config.json");

    deserializeJson(config, parseJsonString(cast(string)config_string));


    auto router = new URLRouter;

    router.post("/github", &incomingGithubEvent);

    auto settings = new HTTPServerSettings;
    settings.port = config.port;
    settings.accessLogToConsole = true;
    settings.options |= HTTPServerOption.parseJsonBody;
    listenHTTP(settings, router);
}

void incomingGithubEvent ( scope HTTPServerRequest req, HTTPServerResponse res )
{
    scope(exit)
        res.writeBody("");

    import std.format;
    auto event = "X-Github-Event" in req.headers;

    if (!event)
    {
        writefln("No github event header found!");
        return;
    }

    auto repo = req.json["repository"]["full_name"].get!string;
    string channel = config.channel;
    string user = config.user;
    string icon = config.icon;

    foreach ( mapping; config.mappings )
        if (mapping.repo == repo)
        {
            if (mapping.channel)
                channel = mapping.channel;
            if (mapping.user)
                user = mapping.user;
            if (mapping.icon)
                icon = mapping.icon;

            break;
        }

    try switch (*event)
    {
        case "ping":
            writefln("received ping");
            return;
        case "issue_comment":
            forward(format(`[%s] New comment on %s [#%s: %s](%s)\n\n**%s wrote:**\n%s`,
                    req.json["repository"]["name"].get!string, "issue",
                    req.json["issue"]["number"].get!long,
                    req.json["issue"]["title"].get!string,
                    req.json["issue"]["html_url"].get!string,
                    req.json["comment"]["user"]["login"].get!string,
                    req.json["comment"]["body"].get!string), user, channel, icon);
            return;
        case "pull_request":
            forward(format(`[%s] **%s** %s pull request [#%s: %s](%s)`,
                    req.json["repository"]["name"].get!string,
                    req.json["pull_request"]["user"]["login"].get!string,
                    req.json["action"],
                    req.json["pull_request"]["number"].get!long,
                    req.json["pull_request"]["title"].get!string,
                    req.json["pull_request"]["html_url"].get!string),
                    user, channel, icon);
            return;
        case "issues":
            forward(format(`[%s] **%s** %s issue [#%s: %s](%s)`,
                    req.json["repository"]["name"].get!string,
                    req.json["issue"]["user"]["login"].get!string,
                    req.json["action"],
                    req.json["issue"]["number"].get!long,
                    req.json["issue"]["title"].get!string,
                    req.json["issue"]["html_url"].get!string),
                    user, channel, icon);
            return;
        case "pull_request_review_comment":
            forward(format(`[%s] New comment on pull request [#%s: %s](%s)\n\n**%s wrote:**\n%s`,
                    req.json["repository"]["name"].get!string,
                    req.json["pull_request"]["id"].get!long,
                    req.json["pull_request"]["title"].get!string,
                    req.json["comment"]["html_url"].get!string,
                    req.json["comment"]["user"]["login"].get!string,
                    req.json["comment"]["body"].get!string),
                    user, channel, icon);
            return;
        case "commit_comment":
            forward(format(`[%s] New comment on commit [%s](%s)\n\n**%s wrote:**\n%s`,
                    req.json["repository"]["name"].get!string,
                    req.json["comment"]["commit_id"].get!string[0..5],
                    req.json["comment"]["html_url"].get!string,
                    req.json["comment"]["user"]["login"].get!string,
                    req.json["comment"]["body"].get!string), user, channel, icon);
            return;
        case "push":
            auto text = format(`[%s:%s] [%s new commits](%s) by %s:`,
                    req.json["repository"]["name"].get!string,
                    req.json["ref"].get!string,
                    req.json["commits"].length,
                    req.json["compare"].get!string,
                    req.json["pusher"]["name"].get!string);
            // TODO: list individual commits here
            forward(text, user, channel, icon);
            return;
        default:
            writefln("received unhandled event %s", *event);
            return;
    }
    catch ( Exception e )
    {
        writefln("Exception: %s %s:%s", e.msg, e.file, e.line);
        forward(format(`{ "text" : "Error: %s at %s:%s" }`, e.msg, e.file,
                e.line));
    }
}

void forward ( string text, string user = null, string channel = null, string icon = null)
{
    writefln("Sending text %s to %s", text, config.mattermost_hook);

    requestHTTP(config.mattermost_hook,
            (scope req)
            {
                req.method = HTTPMethod.POST;
                req.contentType = "application/json";

                auto output = req.bodyWriter;

                with(output)
                {
                    write("{");
                    write(` "text" : "`);
                    write(text);
                    write(` "`);

                    if (user)
                    {
                        write(`, "user" : "`);
                        write(user);
                        write(`"`);
                    }

                    if (channel)
                    {
                        write(`, "channel" : "`);
                        write(channel);
                        write(`"`);
                    }

                    if (icon)
                    {
                        write(`, "icon_url" : "`);
                        write(icon);
                        write(`" `);
                    }

                    write("}");
                }
            },
            (scope res)
            {
                writefln("Response: %s", res.bodyReader.readAllUTF8());
            }
    );
}


