import os from "node:os";

/** Non-loopback IPv4 addresses suitable for LAN clients (excludes typical virtual adapters). */
export function getLanAddresses(): string[] {
  const virtualPrefixes = ["127.", "169.254.", "172.17.", "172.18.", "172.19.", "172.20.", "172.21.", "172.22.", "172.23.", "172.24.", "172.25."];
  const ips: string[] = [];

  for (const ifaces of Object.values(os.networkInterfaces())) {
    if (!ifaces) continue;
    for (const iface of ifaces) {
      const isIpv4 = String(iface.family) === "IPv4" || String(iface.family) === "4";
      if (!isIpv4 || iface.internal) continue;
      if (virtualPrefixes.some((prefix) => iface.address.startsWith(prefix))) continue;
      if (!ips.includes(iface.address)) {
        ips.push(iface.address);
      }
    }
  }

  return ips;
}
