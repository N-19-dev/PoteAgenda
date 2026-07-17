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

export default function SignupPage() {
  const [username, setUsername] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const router = useRouter();

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();

    const normalizedUsername = username.trim().toLowerCase();
    if (!/^[a-z0-9_.]{3,20}$/.test(normalizedUsername)) {
      toast.error("Pseudo invalide (3-20 caractères, lettres/chiffres/_/.)");
      return;
    }

    setIsLoading(true);
    const supabase = createClient();
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: { data: { username: normalizedUsername } },
    });
    setIsLoading(false);

    if (error) {
      toast.error(error.message.includes("already") ? "Cet email est déjà utilisé" : "Inscription impossible");
      return;
    }

    if (data.session) {
      router.push("/groups");
      router.refresh();
    } else {
      toast.success("Vérifie ta boîte mail pour confirmer ton compte");
      router.push("/login");
    }
  }

  return (
    <div className="flex flex-1 flex-col justify-center px-6 py-10">
      <div className="mb-8 flex flex-col items-center gap-2 text-center">
        <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-primary text-primary-foreground">
          <CalendarClock className="h-6 w-6" />
        </div>
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
            minLength={6}
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
  );
}
