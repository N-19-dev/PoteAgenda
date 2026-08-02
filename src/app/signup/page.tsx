"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createClient } from "@/lib/supabase/client";
import { ensureSupabaseReachable } from "@/lib/supabase/health-check";

const AUTH_TIMEOUT_MS = 4500;

function withTimeout<T>(promise: Promise<T>) {
  return Promise.race([
    promise,
    new Promise<never>((_, reject) => {
      window.setTimeout(() => reject(new Error("auth-timeout")), AUTH_TIMEOUT_MS);
    }),
  ]);
}

export default function SignupPage() {
  const [username, setUsername] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const router = useRouter();

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();

    const normalizedUsername = username.trim();

    setIsLoading(true);
    let result;
    try {
      await ensureSupabaseReachable();
      const supabase = createClient();
      result = await withTimeout(
        supabase.auth.signUp({
          email,
          password,
          options: { data: { username: normalizedUsername } },
        }),
      );
    } catch {
      setIsLoading(false);
      toast.error("Supabase est injoignable. Vérifie NEXT_PUBLIC_SUPABASE_URL dans .env.local.");
      return;
    }
    const { data, error } = result;
    setIsLoading(false);

    if (error) {
      toast.error(error.message.includes("already") ? "Cet email est déjà utilisé" : "Inscription impossible");
      return;
    }

    if (data.session) {
      router.push("/agenda");
      router.refresh();
    } else {
      toast.success("Vérifie ta boîte mail pour confirmer ton compte");
      router.push("/login");
    }
  }

  return (
    <div className="relative flex flex-1 flex-col justify-center px-6 py-10">
      <div className="relative mx-auto w-full max-w-sm rounded-lg border border-border bg-card p-6 shadow-sm">
        <div>
          <div className="mb-8 flex flex-col items-center gap-3 text-center">
            <h1 className="text-xl font-semibold tracking-tight">Créer un compte</h1>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-1.5">
              <Label htmlFor="username">Pseudo</Label>
              <Input
                id="username"
                required
                placeholder="alex.b"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                autoComplete="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="password">Mot de passe</Label>
              <Input
                id="password"
                type="password"
                autoComplete="new-password"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
              />
            </div>
            <Button type="submit" className="w-full" disabled={isLoading}>
              {isLoading ? "Création..." : "S'inscrire"}
            </Button>
          </form>

          <p className="mt-6 text-center text-sm text-muted-foreground">
            Déjà un compte ?{" "}
            <Link href="/login" className="font-medium text-foreground underline underline-offset-4">
              Connecte-toi
            </Link>
          </p>
        </div>
      </div>
    </div>
  );
}
