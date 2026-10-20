import { defineExtension } from "voz";

const mailApps = new Set(["com.apple.mail", "com.microsoft.Outlook"]);

export default defineExtension((voz) => {
  voz.on("beforeCleanup", (event, ctx) => {
    if (!mailApps.has(ctx.app.bundleID ?? "")) return;
    const style = typeof voz.config.style === "string" ? `\n${voz.config.style}` : "";
    return {
      prompt: `${event.prompt}\n\nFormat it as an email. Put the greeting on its own line, split the body into short paragraphs and put the sign-off on its own line.${style}`,
    };
  });
});
