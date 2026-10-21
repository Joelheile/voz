import { defineExtension } from "voz";

const mailApps = new Set(["com.apple.mail", "com.microsoft.Outlook"]);

export default defineExtension((voz) => {
  const { style } = voz.settings({
    style: { type: "string", title: "Style", description: "Such as: Start with \"Hi\" and end with \"Best, Joel\".", default: "" },
  });

  voz.on("beforeCleanup", (event, ctx) => {
    if (!mailApps.has(ctx.app.bundleID ?? "")) return;
    return {
      prompt: `${event.prompt}\n\nFormat it as an email. Put the greeting on its own line, split the body into short paragraphs and put the sign-off on its own line.\n${style}`.trimEnd(),
    };
  });
});
