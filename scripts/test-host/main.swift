import Darwin
import Testing
guard dlopen(CommandLine.arguments[1], RTLD_NOW) != nil else { print(String(cString: dlerror())); exit(2) }
await Testing.__swiftPMEntryPoint() as Never
