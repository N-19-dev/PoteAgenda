import { lookup } from "node:dns/promises";
import { NextResponse } from "next/server";

export const runtime = "nodejs";

const CHECK_TIMEOUT_MS = 1200;

export async function GET() {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;

  if (!supabaseUrl) {
    return NextResponse.json({ ok: false, reason: "missing-url" }, { status: 503 });
  }

  try {
    const hostname = new URL(supabaseUrl).hostname;
    await Promise.race([
      lookup(hostname),
      new Promise<never>((_, reject) => {
        setTimeout(() => reject(new Error("dns-timeout")), CHECK_TIMEOUT_MS);
      }),
    ]);
    return NextResponse.json({ ok: true });
  } catch {
    return NextResponse.json({ ok: false, reason: "unreachable" }, { status: 503 });
  }
}
