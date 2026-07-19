using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;

internal static class PalWhipSetup
{
    private const string PayloadResource = "PalWhip.Payload.zip";

    [STAThread]
    private static int Main()
    {
        string extractionRoot = Path.Combine(
            Path.GetTempPath(), "PalWhip-Setup-" + Guid.NewGuid().ToString("N"));

        try
        {
            Directory.CreateDirectory(extractionRoot);
            ExtractPayload(extractionRoot);

            string installer = Path.Combine(extractionRoot, "install.ps1");
            if (!File.Exists(installer))
            {
                throw new FileNotFoundException("The embedded installer payload is incomplete.", installer);
            }

            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = "powershell.exe";
            startInfo.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File \"" + installer + "\"";
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = false;
            startInfo.WorkingDirectory = extractionRoot;

            using (Process process = Process.Start(startInfo))
            {
                if (process == null)
                {
                    throw new InvalidOperationException("Windows could not start the embedded installer.");
                }
                process.WaitForExit();
                if (process.ExitCode != 0)
                {
                    MessageBox.Show(
                        "PalWhip installation did not complete. Review the installer window for the error.",
                        "PalWhip Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return process.ExitCode;
                }
            }

            MessageBox.Show(
                "PalWhip and PalBoombox are installed. You can now launch Palworld.",
                "PalWhip Setup", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return 0;
        }
        catch (Exception error)
        {
            MessageBox.Show(
                "PalWhip Setup failed:\r\n\r\n" + error.Message,
                "PalWhip Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally
        {
            try
            {
                if (Directory.Exists(extractionRoot))
                {
                    Directory.Delete(extractionRoot, true);
                }
            }
            catch
            {
                // A locked temporary file is harmless and Windows will clear
                // the temporary directory later.
            }
        }
    }

    private static void ExtractPayload(string extractionRoot)
    {
        string safeRoot = Path.GetFullPath(extractionRoot)
            .TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;

        using (Stream resource = Assembly.GetExecutingAssembly()
            .GetManifestResourceStream(PayloadResource))
        {
            if (resource == null)
            {
                throw new InvalidDataException("The embedded mod payload is missing.");
            }

            using (ZipArchive archive = new ZipArchive(resource, ZipArchiveMode.Read, false))
            {
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    string relativePath = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
                    string destination = Path.GetFullPath(Path.Combine(extractionRoot, relativePath));
                    if (!destination.StartsWith(safeRoot, StringComparison.OrdinalIgnoreCase))
                    {
                        throw new InvalidDataException("The installer payload contains an unsafe path.");
                    }

                    if (entry.Name.Length == 0)
                    {
                        Directory.CreateDirectory(destination);
                        continue;
                    }

                    string parent = Path.GetDirectoryName(destination);
                    if (!String.IsNullOrEmpty(parent))
                    {
                        Directory.CreateDirectory(parent);
                    }
                    using (Stream input = entry.Open())
                    using (FileStream output = new FileStream(destination, FileMode.Create, FileAccess.Write))
                    {
                        input.CopyTo(output);
                    }
                }
            }
        }
    }
}
