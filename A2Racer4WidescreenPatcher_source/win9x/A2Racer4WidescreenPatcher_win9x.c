/*
 * A2 Racer 4 Widescreen Patcher for Windows 95, 98 and Me.
 *
 * Go has never supported Windows 9x, so this is a separate native program. It
 * has to do exactly what ../A2Racer4WidescreenPatcher.go does: keep the two in
 * step, and compare the files both write before each release. It only uses
 * functions that exist since Windows 95, and no C runtime.
 *
 * Build it from the parent folder, see ../README.md.
 */
#include <windows.h>

#define PATCHER_VERSION "1.0.9"
#define GAME_FILE "spel.dat"
#define BACKUP_DIR "4x3_backup"
#define EXTRA_CAR_OVERLAY "overlay7.ini"
#define MIN_GAME_SIZE 0x1B3932
#define PATH_SIZE 600

/* Patched HUD layout files (the dashboard fix), installed next to spel.dat. */
#define EMBED(sym, file)                                                       \
	__asm__(".section .rdata,\"dr\"\n_" #sym ":\n.incbin \"" file              \
		"\"\n_" #sym "_end:\n.text\n");                                        \
	extern const char sym[], sym##_end[]

EMBED(overlay0, "overlays/overlay0.ini");
EMBED(overlay1, "overlays/overlay1.ini");
EMBED(overlay2, "overlays/overlay2.ini");
EMBED(overlay3, "overlays/overlay3.ini");
EMBED(overlay4, "overlays/overlay4.ini");
EMBED(overlay5, "overlays/overlay5.ini");
EMBED(overlay6, "overlays/overlay6.ini");
EMBED(overlay7, "overlays/overlay7.ini");

static const struct {
	const char *name;
	const char *start;
	const char *end;
} overlays[] = {
	{"overlay0.ini", overlay0, overlay0_end},
	{"overlay1.ini", overlay1, overlay1_end},
	{"overlay2.ini", overlay2, overlay2_end},
	{"overlay3.ini", overlay3, overlay3_end},
	{"overlay4.ini", overlay4, overlay4_end},
	{"overlay5.ini", overlay5, overlay5_end},
	{"overlay6.ini", overlay6, overlay6_end},
	{"overlay7.ini", overlay7, overlay7_end},
};

static const DWORD width_offsets[] = {
	0x1B3798, 0x1B37EC, 0x1B3800, 0x1B3814, 0x1B3864, 0x1B3878,
	0x1B388C, 0x1B38A0, 0x1B38B4, 0x1B3904, 0x1B3918, 0x1B392C,
};

static const DWORD height_offsets[] = {
	0x1B379C, 0x1B37F0, 0x1B3804, 0x1B3818, 0x1B3868, 0x1B387C,
	0x1B3890, 0x1B38A4, 0x1B38B8, 0x1B3908, 0x1B391C, 0x1B3930,
};

/* The code changes, see applyWidescreenPatch in the Go patcher for what each does. */
static const struct {
	DWORD offset;
	const char *label;
	int size;
	unsigned char original[11];
	unsigned char replacement[11];
} code_patches[] = {
	{0x0C0E57, "aspect division", 6,
		{0xDA, 0x35, 0x98, 0x37, 0x5B, 0x00},
		{0xDA, 0x35, 0xD0, 0x73, 0x59, 0x00}},
	{0x0C0E8A, "horizontal clip x", 7,
		{0xC7, 0x46, 0x14, 0x00, 0x00, 0x80, 0xBF},
		{0xC7, 0x46, 0x14, 0x00, 0x00, 0xA0, 0xBF}},
	{0x0C0E96, "horizontal clip width", 7,
		{0xC7, 0x46, 0x1C, 0x00, 0x00, 0x00, 0x40},
		{0xC7, 0x46, 0x1C, 0x00, 0x00, 0x20, 0x40}},
	{0x0BC0F0, "texture memory probe", 11,
		{0xB8, 0x00, 0x10, 0x00, 0x00, 0xE8, 0x06, 0xD3, 0x09, 0x00, 0x53},
		{0xC7, 0x81, 0xA1, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04, 0xC3}},
};

static HANDLE input, output;
static char message[1500];
static char error[1500];
static char earlier_error[1500];
static char game_dir[PATH_SIZE];

/* No C runtime, but the compiler may still call these. */
void *memcpy(void *to, const void *from, unsigned int size)
{
	char *d = to;
	const char *s = from;

	while (size--)
		*d++ = *s++;
	return to;
}

void *memset(void *to, int value, unsigned int size)
{
	char *d = to;

	while (size--)
		*d++ = (char)value;
	return to;
}

static BOOL same_bytes(const void *a, const void *b, DWORD size)
{
	const char *x = a;
	const char *y = b;

	while (size--)
		if (*x++ != *y++)
			return FALSE;
	return TRUE;
}

static void say(const char *text)
{
	DWORD written;

	WriteFile(output, text, lstrlenA(text), &written, NULL);
}

#define SAY(...) (wsprintfA(message, __VA_ARGS__), say(message))
#define FAIL(...) (wsprintfA(error, __VA_ARGS__), FALSE)

/* Keeps the current error while the next one is built from it. */
static const char *earlier(void)
{
	lstrcpyA(earlier_error, error);
	return earlier_error;
}

/* The last Windows error as readable text for the console. */
static const char *system_error(void)
{
	static char text[300];
	DWORD code = GetLastError();
	int size;

	if (!FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, NULL,
			code, 0, text, sizeof(text), NULL)) {
		wsprintfA(text, "error %lu", code);
		return text;
	}

	size = lstrlenA(text);
	while (size > 0 && (text[size - 1] == '\r' || text[size - 1] == '\n' ||
			text[size - 1] == ' ' || text[size - 1] == '.'))
		text[--size] = 0;

	CharToOemA(text, text);
	return text;
}

/* Keeps what comes after a line, because a pipe can deliver several at once. */
static BOOL read_line(char *line, int size)
{
	static char buffer[512];
	static DWORD filled, used;
	BOOL any = FALSE;
	int length = 0;

	for (;;) {
		char c;

		if (used == filled) {
			used = filled = 0;
			if (!ReadFile(input, buffer, sizeof(buffer), &filled, NULL) || filled == 0) {
				filled = 0;
				break;
			}
		}

		c = buffer[used++];
		any = TRUE;
		if (c == '\n')
			break;
		if (length < size - 1)
			line[length++] = c;
	}

	line[length] = 0;
	return any;
}

static BOOL is_space(char c)
{
	return c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\f' || c == '\v';
}

static void join_path(char *path, const char *dir, const char *name)
{
	int size = lstrlenA(dir);

	lstrcpyA(path, dir);
	if (size > 0 && dir[size - 1] != '\\' && dir[size - 1] != ':')
		lstrcatA(path, "\\");
	lstrcatA(path, name);
}

static const char *base_name(const char *path)
{
	const char *name = path;

	for (; *path; path++)
		if (*path == '\\')
			name = path + 1;
	return name;
}

/* Accepts a folder the way people tend to enter it: surrounded by quotes. */
static void clean_path(char *path)
{
	char *start = path;
	char *to = path;
	char *c;
	int size;

	while (is_space(*start))
		start++;
	size = lstrlenA(start);
	while (size > 0 && is_space(start[size - 1]))
		size--;

	if (size >= 2 && (start[0] == '"' || start[0] == '\'') && start[size - 1] == start[0]) {
		start++;
		size -= 2;
	}

	for (c = start; c < start + size; c++)
		*to++ = *c == '/' ? '\\' : *c;
	*to = 0;

	size = lstrlenA(path);
	while (size > 1 && path[size - 1] == '\\' && path[size - 2] != ':')
		path[--size] = 0;
}

static BOOL is_dir(const char *path)
{
	DWORD attributes = GetFileAttributesA(path);

	return attributes != 0xFFFFFFFF && (attributes & FILE_ATTRIBUTE_DIRECTORY);
}

/* Fills in the path of name in dir, with its real spelling when it exists. */
static BOOL find_file(const char *dir, const char *name, char *path)
{
	WIN32_FIND_DATAA found;
	HANDLE search;

	join_path(path, dir, name);
	search = FindFirstFileA(path, &found);
	if (search == INVALID_HANDLE_VALUE)
		return FALSE;
	FindClose(search);

	if (found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
		return FALSE;

	join_path(path, dir, found.cFileName);
	return TRUE;
}

static char *read_file(const char *path, DWORD *size)
{
	HANDLE file;
	char *data;
	DWORD done = 0;

	file = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING,
		FILE_ATTRIBUTE_NORMAL, NULL);
	if (file == INVALID_HANDLE_VALUE)
		return NULL;

	*size = GetFileSize(file, NULL);
	data = *size == 0xFFFFFFFF ? NULL : HeapAlloc(GetProcessHeap(), 0, *size + 1);
	if (data != NULL) {
		while (done < *size) {
			DWORD part;

			if (!ReadFile(file, data + done, *size - done, &part, NULL) || part == 0) {
				HeapFree(GetProcessHeap(), 0, data);
				data = NULL;
				break;
			}
			done += part;
		}
	}

	CloseHandle(file);
	return data;
}

/* Writes data and reads it back, so a write that silently did not happen is reported. */
static BOOL write_verified(const char *path, const char *data, DWORD size)
{
	HANDLE file;
	DWORD written = 0;
	DWORD back_size;
	char *back;
	BOOL same;

	file = CreateFileA(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
	if (file == INVALID_HANDLE_VALUE)
		return FAIL("%s: %s", path, system_error());

	if (!WriteFile(file, data, size, &written, NULL) || written != size) {
		const char *reason = system_error();

		CloseHandle(file);
		return FAIL("%s: %s", path, reason);
	}
	if (!CloseHandle(file))
		return FAIL("%s: %s", path, system_error());

	back = read_file(path, &back_size);
	if (back == NULL)
		return FAIL("could not read %s back after writing: %s", path, system_error());

	same = back_size == size && same_bytes(back, data, size);
	HeapFree(GetProcessHeap(), 0, back);
	if (!same)
		return FAIL("%s does not contain the patched data after writing", path);

	return TRUE;
}

/* Where an original file is moved to. An existing backup is never overwritten,
   since it may hold the untouched 4:3 file. */
static BOOL backup_path_for(const char *name, char *path)
{
	static char dir[PATH_SIZE];

	join_path(dir, game_dir, BACKUP_DIR);
	if (!CreateDirectoryA(dir, NULL) && !is_dir(dir))
		return FAIL("could not create %s folder: %s", BACKUP_DIR, system_error());

	join_path(path, dir, name);
	if (GetFileAttributesA(path) != 0xFFFFFFFF) {
		static char stamped[PATH_SIZE];
		const char *extension = name + lstrlenA(name);
		SYSTEMTIME now;
		int stem;

		while (extension > name && *extension != '.')
			extension--;
		if (*extension != '.')
			extension = name + lstrlenA(name);
		stem = (int)(extension - name);

		GetLocalTime(&now);
		lstrcpynA(stamped, name, stem + 1);
		wsprintfA(stamped + stem, "_%04d%02d%02d_%02d%02d%02d%s", now.wYear, now.wMonth,
			now.wDay, now.wHour, now.wMinute, now.wSecond, extension);
		join_path(path, dir, stamped);
	}

	return TRUE;
}

/* Suggests the patcher's own folder when spel.dat is there, otherwise the current one. */
static void default_game_dir(char *dir)
{
	static char probe[PATH_SIZE];
	char *c;

	if (GetModuleFileNameA(NULL, dir, MAX_PATH) != 0) {
		for (c = dir + lstrlenA(dir); c > dir; c--) {
			if (*c == '\\') {
				*c = 0;
				break;
			}
		}
		if (find_file(dir, GAME_FILE, probe))
			return;
	}

	if (GetCurrentDirectoryA(MAX_PATH, dir) == 0)
		lstrcpyA(dir, ".");
}

static BOOL ask_game_dir(void)
{
	static char suggested[PATH_SIZE];
	static char line[300];
	static char path[PATH_SIZE];

	default_game_dir(suggested);

	say("Enter the A2 Racer 4 game folder (the folder that contains " GAME_FILE ").\r\n");
	say("Press Enter to use this folder:\r\n");
	SAY("  %s\r\n", suggested);
	say("Game folder: ");

	if (!read_line(line, sizeof(line)))
		return FAIL("EOF");

	clean_path(line);
	lstrcpyA(game_dir, line[0] ? line : suggested);

	if (!is_dir(game_dir))
		return FAIL("%s is not a folder", game_dir);

	if (!find_file(game_dir, GAME_FILE, path))
		return FAIL("there is no %s in %s. Choose the A2 Racer 4 game folder", GAME_FILE, game_dir);

	say("\r\n");
	return TRUE;
}

/* Reads a number of 3 to 5 digits. */
static BOOL read_number(const char **text, int *value)
{
	const char *c = *text;
	int digits = 0;

	*value = 0;
	while (*c >= '0' && *c <= '9' && digits <= 5) {
		*value = *value * 10 + (*c++ - '0');
		digits++;
	}

	*text = c;
	return digits >= 3 && digits <= 5;
}

static BOOL ask_resolution(int *width, int *height)
{
	static char line[100];
	const char *c = line;

	say("Enter desired 16:9 resolution, for example 2560x1440: ");

	if (!read_line(line, sizeof(line)))
		return FAIL("EOF");

	while (is_space(*c))
		c++;
	if (!read_number(&c, width))
		return FAIL("invalid resolution format. Use something like 2560x1440");
	while (is_space(*c))
		c++;
	if (*c != 'x' && *c != 'X')
		return FAIL("invalid resolution format. Use something like 2560x1440");
	c++;
	while (is_space(*c))
		c++;
	if (!read_number(&c, height))
		return FAIL("invalid resolution format. Use something like 2560x1440");
	while (is_space(*c))
		c++;
	if (*c != 0)
		return FAIL("invalid resolution format. Use something like 2560x1440");

	if (*width <= 0 || *height <= 0 || *width > 65535 || *height > 65535)
		return FAIL("resolution values must be between 1 and 65535");

	/* The patch was designed for 16:9. Warn, but do not reject, so custom 16:9-ish
	   modes like 1366x768 can still be tested. */
	if (*width * 100 < *height * 170 || *width * 100 > *height * 182)
		SAY("Warning: %dx%d is not very close to 16:9. Continuing anyway.\r\n", *width, *height);

	return TRUE;
}

static void put_u16(char *data, DWORD offset, int value)
{
	data[offset] = (char)value;
	data[offset + 1] = (char)(value >> 8);
}

static BOOL apply_widescreen_patch(char *data, int width, int height)
{
	unsigned int i;
	int aspect_denominator;

	for (i = 0; i < sizeof(width_offsets) / sizeof(width_offsets[0]); i++)
		put_u16(data, width_offsets[i], width);

	for (i = 0; i < sizeof(height_offsets) / sizeof(height_offsets[0]); i++)
		put_u16(data, height_offsets[i], height);

	/* Keep a 4:3 projection reference width for the chosen output height. */
	aspect_denominator = (height * 4 + 1) / 3;
	put_u16(data, 0x1973D0, aspect_denominator & 0xFFFF);
	put_u16(data, 0x1973D2, aspect_denominator >> 16);

	for (i = 0; i < sizeof(code_patches) / sizeof(code_patches[0]); i++) {
		char *current = data + code_patches[i].offset;
		int size = code_patches[i].size;

		if (same_bytes(current, code_patches[i].replacement, size))
			continue; /* already patched */

		if (!same_bytes(current, code_patches[i].original, size))
			return FAIL("%s bytes did not match expected original pattern at 0x%lX. This may be the wrong spel.dat version",
				code_patches[i].label, code_patches[i].offset);

		memcpy(current, code_patches[i].replacement, size);
	}

	return TRUE;
}

/* Everything up to moving the original happens before spel.dat is touched. */
static BOOL unchanged(void)
{
	lstrcatA(error, ". Nothing was changed");
	return FALSE;
}

static BOOL patch_in_place(int width, int height)
{
	static char input_path[PATH_SIZE];
	static char backup_path[PATH_SIZE];
	char *data;
	DWORD size;

	find_file(game_dir, GAME_FILE, input_path);

	data = read_file(input_path, &size);
	if (data == NULL) {
		FAIL("could not read " GAME_FILE ": %s", system_error());
		return unchanged();
	}

	if (size < MIN_GAME_SIZE) {
		FAIL(GAME_FILE " is smaller than expected; wrong file?");
		return unchanged();
	}

	if (data[0] != 'M' || data[1] != 'Z') {
		FAIL(GAME_FILE " does not look like a Windows PE executable");
		return unchanged();
	}

	if (!apply_widescreen_patch(data, width, height))
		return unchanged();

	if (!backup_path_for(base_name(input_path), backup_path))
		return unchanged();

	if (!MoveFileA(input_path, backup_path)) {
		FAIL("could not move original " GAME_FILE " to %s: %s", backup_path, system_error());
		return unchanged();
	}

	if (!write_verified(input_path, data, size)) {
		/* Try to restore the original if writing fails. */
		DeleteFileA(input_path);
		if (!MoveFileA(backup_path, input_path))
			return FAIL("could not write patched " GAME_FILE ": %s. The original is still in %s",
				earlier(), backup_path);
		return FAIL("could not write patched " GAME_FILE ": %s. The original " GAME_FILE " was put back",
			earlier());
	}

	HeapFree(GetProcessHeap(), 0, data);
	return TRUE;
}

/* Copies the patched HUD overlay files into the game folder and moves the files
   they replace to the backup folder. overlay7.ini comes with the "Schaduw" extra
   car update, which would overwrite it again, so it is only replaced when that
   update is already installed. */
static BOOL install_overlays(void)
{
	static char target[PATH_SIZE];
	static char backup_path[PATH_SIZE];
	unsigned int i;

	for (i = 0; i < sizeof(overlays) / sizeof(overlays[0]); i++) {
		const char *name = overlays[i].name;
		const char *data = overlays[i].start;
		DWORD size = (DWORD)(overlays[i].end - overlays[i].start);
		BOOL exists = find_file(game_dir, name, target);

		if (!exists && lstrcmpA(name, EXTRA_CAR_OVERLAY) == 0) {
			SAY("Skipped %s: the \"Schaduw\" extra car update is not installed.\r\n", name);
			say("  Install that update first, then run the patcher again.\r\n");
			continue;
		}

		backup_path[0] = 0;
		if (exists) {
			DWORD current_size;
			char *current = read_file(target, &current_size);
			BOOL same;

			if (current == NULL)
				return FAIL("could not read %s: %s", target, system_error());

			same = current_size == size && same_bytes(current, data, size);
			HeapFree(GetProcessHeap(), 0, current);
			if (same) {
				SAY("%s is already up to date.\r\n", name);
				continue;
			}

			if (!backup_path_for(base_name(target), backup_path))
				return FALSE;

			if (!MoveFileA(target, backup_path))
				return FAIL("could not move original %s to %s: %s", name, backup_path, system_error());
		}

		if (!write_verified(target, data, size)) {
			/* Try to restore the original if writing fails. */
			if (backup_path[0] != 0) {
				DeleteFileA(target);
				if (!MoveFileA(backup_path, target))
					return FAIL("could not write %s: %s. The original is still in %s", name, earlier(), backup_path);
			}
			return FAIL("could not write %s: %s", name, earlier());
		}

		SAY("Installed %s\r\n", name);
	}

	return TRUE;
}

/* Does the actual work. Every failure is reported, together with what it means
   for the game files, so the patcher never fails silently. */
static BOOL run(void)
{
	int width, height;

	say("A2 Racer 4 Widescreen Patcher v" PATCHER_VERSION "\r\n");
	say("--------------------------------\r\n\r\n");

	/* Newer Windows has administrator rights and redirected writes, which only
	   the other Windows versions of the patcher deal with. */
	if (!(GetVersion() & 0x80000000)) {
		say("Error: this version is for Windows 95, 98 and Me. Use A2Racer4WidescreenPatcher_32bit.exe\r\n");
		say("Nothing was changed.\r\n");
		return FALSE;
	}

	if (!ask_game_dir() || !ask_resolution(&width, &height)) {
		SAY("Error: %s\r\n", error);
		say("Nothing was changed.\r\n");
		return FALSE;
	}

	if (!patch_in_place(width, height)) {
		SAY("\r\nPatch failed: %s\r\n", error);
		return FALSE;
	}

	say("\r\n");
	SAY("Created patched " GAME_FILE " for %dx%d.\r\n", width, height);
	say("The texture memory crash fix for modern graphics cards is included.\r\n\r\n");

	if (!install_overlays()) {
		SAY("\r\nCopying the HUD files failed: %s\r\n", error);
		say(GAME_FILE " is patched, but not every HUD file was installed.\r\n");
		say("Fix the problem and run the patcher again.\r\n");
		return FALSE;
	}

	say("\r\nDone. Original files were moved to the " BACKUP_DIR " folder in:\r\n");
	SAY("  %s\r\n", game_dir);
	return TRUE;
}

void __stdcall start(void)
{
	static char line[16];
	BOOL ok;

	input = GetStdHandle(STD_INPUT_HANDLE);
	output = GetStdHandle(STD_OUTPUT_HANDLE);

	/* What is typed in a console is in the OEM code page. */
	SetFileApisToOEM();

	ok = run();

	/* Windows 9x cannot tell whether this console closes with the patcher, so
	   always keep the result readable. */
	if (GetFileType(input) == FILE_TYPE_CHAR) {
		say("\r\nPress Enter to close.");
		read_line(line, sizeof(line));
	}

	ExitProcess(ok ? 0 : 1);
}
