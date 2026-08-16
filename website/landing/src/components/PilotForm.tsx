import { zodResolver } from "@hookform/resolvers/zod";
import { Link } from "@tanstack/react-router";
import { ArrowRight, Check, Loader2 } from "lucide-react";
import { useState, type ReactNode } from "react";
import { useForm, type UseFormReturn } from "react-hook-form";

import {
  Form,
  FormControl,
  FormDescription,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import {
  pilotApplicationSchema,
  submitPilotApplication,
  type PilotApplication,
} from "@/lib/pilot-application";
import { CONTACT_EMAIL, LEGAL_NAME, MIN_MACOS } from "@/lib/site";

/**
 * The pilot application form.
 *
 * This replaced a `mailto:` link. A mail client is the highest-drop-off CTA
 * there is, and it captures nothing — no list, no counts, no way to tell whether
 * an applicant can even run the app. The three checkboxes are the hard gates
 * from REQUIREMENTS: a teacher who cannot tick them cannot take part, and it is
 * kinder to say so on the form than in a reply a week later.
 */
export function PilotForm() {
  const [sent, setSent] = useState(false);
  const [failure, setFailure] = useState<string | null>(null);

  const form = useForm<PilotApplication>({
    resolver: zodResolver(pilotApplicationSchema),
    defaultValues: {
      name: "",
      email: "",
      school: "",
      teaches: "",
      classSize: "",
      notes: "",
      usesClassroom: false,
      hasMac: false,
      hasZoom: false,
      understandsConsent: false,
      website: "",
    },
  });

  async function onSubmit(values: PilotApplication) {
    setFailure(null);
    try {
      await submitPilotApplication({ data: values });
      setSent(true);
    } catch (error) {
      setFailure(
        error instanceof Error ? error.message : "Something went wrong. Please try again.",
      );
    }
  }

  if (sent) {
    return (
      <div className="rounded-3xl border border-border bg-card p-9 text-center sm:p-11">
        <div className="mx-auto grid h-12 w-12 place-items-center rounded-full bg-primary/15">
          <Check className="text-primary" size={22} />
        </div>
        <h3 className="mt-6 text-xl font-semibold">Application received</h3>
        <p className="mt-3 text-muted-foreground">
          {LEGAL_NAME} reads every one and replies personally, usually within{" "}
          <strong className="text-foreground">2–3 business days</strong>, from{" "}
          <a className="text-primary underline underline-offset-4" href={`mailto:${CONTACT_EMAIL}`}>
            {CONTACT_EMAIL}
          </a>
          . Worth adding that address to your contacts so the reply doesn't land in spam.
        </p>
        <p className="mt-3 text-sm text-muted-foreground">
          There's nothing to do until then. If you haven't heard anything after three business days,
          email that address directly — it means something went wrong on our end, not yours.
        </p>
        <Link
          to="/"
          className="mt-8 inline-flex min-h-11 items-center rounded-full border border-border px-6 text-sm transition-colors hover:bg-accent"
        >
          Back to site
        </Link>
      </div>
    );
  }

  return (
    <Form {...form}>
      <form
        onSubmit={form.handleSubmit(onSubmit)}
        className="relative rounded-3xl border border-border bg-card p-7 sm:p-9"
        noValidate
      >
        <div className="grid gap-5 sm:grid-cols-2">
          <FormField
            control={form.control}
            name="name"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Your name</FormLabel>
                <FormControl>
                  <Input autoComplete="name" {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />
          <FormField
            control={form.control}
            name="email"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Email</FormLabel>
                <FormControl>
                  <Input type="email" autoComplete="email" {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />
          <FormField
            control={form.control}
            name="school"
            render={({ field }) => (
              <FormItem>
                <FormLabel>School or organization</FormLabel>
                <FormControl>
                  <Input autoComplete="organization" {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />
          <FormField
            control={form.control}
            name="teaches"
            render={({ field }) => (
              <FormItem>
                <FormLabel>What you teach</FormLabel>
                <FormControl>
                  <Input placeholder="e.g. 7th grade math" {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />
          <FormField
            control={form.control}
            name="classSize"
            render={({ field }) => (
              <FormItem>
                <FormLabel>
                  Typical class size <span className="text-muted-foreground">(optional)</span>
                </FormLabel>
                <FormControl>
                  <Input inputMode="numeric" placeholder="e.g. 24" {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />
        </div>

        <FormField
          control={form.control}
          name="notes"
          render={({ field }) => (
            <FormItem className="mt-5">
              <FormLabel>
                Anything else <span className="text-muted-foreground">(optional)</span>
              </FormLabel>
              <FormControl>
                <Textarea
                  rows={3}
                  placeholder="What made you click? Which students are you worried about?"
                  {...field}
                />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />

        <fieldset className="mt-8 space-y-4 border-t border-border pt-7">
          <legend className="sr-only">Requirements</legend>
          <GateField
            name="hasMac"
            form={form}
            label={`I have a Mac running ${MIN_MACOS} or later`}
          />
          <GateField
            name="hasZoom"
            form={form}
            label="I teach live on Zoom and can connect my account"
          />
          <GateField
            name="usesClassroom"
            form={form}
            label="I use Google Classroom"
            description="Optional — it gives Anchor more to work with, but Anchor works fine without it."
          />
          <GateField
            name="understandsConsent"
            form={form}
            label="I'll get whatever permission my school requires"
            description={
              <>
                Anchor runs on your own Mac and never sends student data to a server. The{" "}
                <Link className="text-primary underline underline-offset-4" to="/privacy">
                  Privacy Policy
                </Link>{" "}
                explains what that means for FERPA and COPPA.
              </>
            }
          />
        </fieldset>

        {/* Honeypot — off-screen rather than display:none, which some bots skip. */}
        <div aria-hidden className="absolute left-[-9999px] h-px w-px overflow-hidden">
          <label htmlFor="website">Website</label>
          <input id="website" tabIndex={-1} autoComplete="off" {...form.register("website")} />
        </div>

        {failure && (
          <p role="alert" className="mt-6 text-sm text-destructive">
            {failure}
          </p>
        )}

        <button
          type="submit"
          disabled={form.formState.isSubmitting}
          className="mt-8 inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-full bg-primary px-7 font-medium text-primary-foreground transition-transform duration-300 hover:scale-[1.02] disabled:pointer-events-none disabled:opacity-60"
        >
          {form.formState.isSubmitting ? (
            <>
              <Loader2 className="animate-spin" size={18} /> Sending
            </>
          ) : (
            <>
              Apply for the pilot <ArrowRight size={18} />
            </>
          )}
        </button>
        <p className="mt-4 text-center text-sm text-muted-foreground">
          Applying means you accept the{" "}
          <Link className="text-primary underline underline-offset-4" to="/pilot-terms">
            Pilot Program Terms
          </Link>
          . Or email{" "}
          <a className="text-primary underline underline-offset-4" href={`mailto:${CONTACT_EMAIL}`}>
            {CONTACT_EMAIL}
          </a>{" "}
          if you'd rather just talk first.
        </p>
      </form>
    </Form>
  );
}

function GateField({
  form,
  name,
  label,
  description,
}: {
  form: UseFormReturn<PilotApplication>;
  name: "hasMac" | "hasZoom" | "usesClassroom" | "understandsConsent";
  label: string;
  description?: ReactNode;
}) {
  return (
    <FormField
      control={form.control}
      name={name}
      render={({ field }) => (
        <FormItem className="flex flex-row items-start gap-3 space-y-0">
          <FormControl>
            <Checkbox
              // The design system's --radius makes a 16px `rounded-sm` box look
              // circular, and a consent checkbox must not read as a radio.
              className="mt-1 rounded-[4px]"
              checked={field.value === true}
              onCheckedChange={(checked) => field.onChange(checked === true)}
            />
          </FormControl>
          <div className="space-y-1">
            <FormLabel className="font-normal leading-normal">{label}</FormLabel>
            {description && <FormDescription>{description}</FormDescription>}
            <FormMessage />
          </div>
        </FormItem>
      )}
    />
  );
}
