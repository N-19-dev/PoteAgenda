"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { CalendarClock } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { createClient } from "@/lib/supabase/client";

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const router = useRouter();

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setIsLoading(true);
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    setIsLoading(false);

    if (error) {
      toast.error("Email ou mot de passe incorrect");
      return;
    }
    router.push("/groups");
    router.refresh();
  }

  return (
    <div className="flex flex-1 flex-col justify-center px-6 py-10">
      <div className="mb-8 flex flex-col items-center gap-2 text-center">
        <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-primary text-primary-foreground">
          <CalendarClock className="h-6 w-6" />
        </div>
        <h1 className="text-xl font-semibold tracking-tight">PoteAgenda</h1>
        <p className="text-sm text-muted-foreground">
          Trouve un créneau libre avec tes potes, sans exposer ton emploi du temps.
        </p>
      </div>

      <form onSubmit={handleSubmit} className="space-y-4">
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
            autoComplete="current-password"
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
        </div>
        <Button type="submit" className="w-full" disabled={isLoading}>
          {isLoading ? "Connexion..." : "Se connecter"}
        </Button>
      </form>

      <p className="mt-6 text-center text-sm text-muted-foreground">
        Pas encore de compte ?{" "}
        <Link href="/signup" className="font-medium text-foreground underline underline-offset-4">
          Inscris-toi
        </Link>
      </p>
    </div>
  );
}
