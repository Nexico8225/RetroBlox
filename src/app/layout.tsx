import type { Metadata, Viewport } from "next";
import "./globals.css";
import { Toaster } from "@/components/ui/toaster";
import { Providers } from "@/components/retro/Providers";

// Without this, phones render the page on a ~980px virtual canvas and everything
// looks zoomed-out / cut off. This pins the layout to the real device width.
export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  themeColor: "#1b5e9e",
};

export const metadata: Metadata = {
  title: "RetroBlox",
  description:
    "RetroBlox is the old-school game platform. Publish your Unity, Godot or any-engine games, download and play classics, add friends and rate games - all in glorious 2006 style.",
  icons: {
    icon: "/retro/logo.png",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className="antialiased">
        <Providers>{children}</Providers>
        <Toaster />
      </body>
    </html>
  );
}
