/*
 * A2 Racer 4 Fixes for 32-bit Windows, from Windows 95 through 10.
 *
 * Current Go versions only run on Windows 10 or newer, so this is a separate
 * native program. It has to do exactly what ../A2Racer4Fixes.go does:
 * keep the two in step, and compare the files both write before each release. It
 * imports only functions that exist since Windows 95, looks up anything newer at
 * runtime, and uses no C runtime.
 *
 * Build it from this folder, see ../README.md.
 */
#include <windows.h>

#define PATCHER_VERSION "1.1.1"
#define GAME_FILE "spel.dat"
#define BACKUP_DIR "4x3_backup"
#define EXTRA_CAR_OVERLAY "overlay7.ini"
#define MIN_GAME_SIZE 0x1B3932
#define PATH_SIZE 600

static const char *const overlay_names[] = {
	"overlay0.ini", "overlay1.ini", "overlay2.ini", "overlay3.ini",
	"overlay4.ini", "overlay5.ini", "overlay6.ini", EXTRA_CAR_OVERLAY,
};

static const DWORD width_offsets[] = {
	0x1B3798, 0x1B37EC, 0x1B3800, 0x1B3814, 0x1B3864, 0x1B3878,
	0x1B388C, 0x1B38A0, 0x1B38B4, 0x1B3904, 0x1B3918, 0x1B392C,
};

static const DWORD height_offsets[] = {
	0x1B379C, 0x1B37F0, 0x1B3804, 0x1B3818, 0x1B3868, 0x1B387C,
	0x1B3890, 0x1B38A4, 0x1B38B8, 0x1B3908, 0x1B391C, 0x1B3930,
};

/* The code changes, see applyPatch in the Go patcher for what each does. */
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
	{0x07CDD1, "HUD scale", 6,
		{0xDA, 0x35, 0x98, 0x37, 0x5B, 0x00},
		{0xDA, 0x35, 0xD0, 0x73, 0x59, 0x00}},
	{0x07FE55, "HUD position", 6,
		{0xDB, 0x05, 0x98, 0x37, 0x5B, 0x00},
		{0xDB, 0x05, 0xD0, 0x73, 0x59, 0x00}},
	{0x080534, "HUD position", 6,
		{0xDB, 0x05, 0x98, 0x37, 0x5B, 0x00},
		{0xDB, 0x05, 0xD0, 0x73, 0x59, 0x00}},
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

	say("Enter desired resolution, for example 2560x1440: ");

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

	return TRUE;
}

static void put_u16(char *data, DWORD offset, int value)
{
	data[offset] = (char)value;
	data[offset + 1] = (char)(value >> 8);
}

static void put_u32(char *data, DWORD offset, DWORD value)
{
	put_u16(data, offset, (int)(value & 0xFFFF));
	put_u16(data, offset + 2, (int)(value >> 16));
}

/* numerator/denominator as a 32-bit float, rounded to nearest. It uses only
   integers, so every build of the patcher writes the same bytes. */
static DWORD float_bits(DWORD numerator, DWORD denominator)
{
	DWORD exponent = 127;
	DWORD mantissa = 0;
	int i;

	while (numerator < denominator) {
		numerator *= 2;
		exponent--;
	}
	while (numerator >= denominator * 2) {
		denominator *= 2;
		exponent++;
	}

	for (i = 0; i < 24; i++) {
		mantissa *= 2;
		if (numerator >= denominator) {
			mantissa++;
			numerator -= denominator;
		}
		numerator *= 2;
	}
	if (numerator >= denominator) {
		mantissa++;
		if (mantissa == 1UL << 24) {
			mantissa = 1UL << 23;
			exponent++;
		}
	}

	return exponent << 23 | (mantissa & 0x7FFFFF);
}

static const unsigned char clip_x_opcode[] = {0xC7, 0x46, 0x14};
static const unsigned char clip_width_opcode[] = {0xC7, 0x46, 0x1C};

static BOOL apply_patch(char *data, int width, int height)
{
	unsigned int i;
	int aspect_denominator;

	for (i = 0; i < sizeof(width_offsets) / sizeof(width_offsets[0]); i++)
		put_u16(data, width_offsets[i], width);

	for (i = 0; i < sizeof(height_offsets) / sizeof(height_offsets[0]); i++)
		put_u16(data, height_offsets[i], height);

	/* Keep a 4:3 projection reference width for the chosen output height. */
	aspect_denominator = (height * 4 + 1) / 3;
	put_u32(data, 0x1973D0, aspect_denominator);

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

	/* The horizontal view for this screen shape: with the vertical view fixed at
	   +-0.75, +-0.75*width/height gives square pixels, and exactly +-1 at 4:3. */
	if (!same_bytes(data + 0x0C0E8A, clip_x_opcode, 3))
		return FAIL("horizontal clip x bytes did not match expected original pattern at 0xC0E8A. This may be the wrong spel.dat version");
	if (!same_bytes(data + 0x0C0E96, clip_width_opcode, 3))
		return FAIL("horizontal clip width bytes did not match expected original pattern at 0xC0E96. This may be the wrong spel.dat version");

	put_u32(data, 0x0C0E8A + 3, float_bits(3 * width, 4 * height) | 0x80000000);
	put_u32(data, 0x0C0E96 + 3, float_bits(3 * width, 2 * height));

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

	if (!apply_patch(data, width, height))
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

/* How far HUD elements attached to a screen edge move, in the game's HUD units.
   The game places HUD x at x*0.99/320-1 in view space, and the view reaches
   +-0.75*width/height, so the edges move by (0.75*width/height-1)*320/0.99,
   which is 0 at 4:3. */
static int hud_shift(int width, int height)
{
	int numerator = (3 * width - 4 * height) * 8000;
	int denominator = 99 * height;

	if (numerator < 0)
		return (numerator - denominator / 2) / denominator;
	return (numerator + denominator / 2) / denominator;
}

static BOOL has_prefix(const char *text, const char *prefix)
{
	while (*prefix) {
		char a = *text++, b = *prefix++;

		if (a >= 'a' && a <= 'z')
			a = (char)(a - 32);
		if (a != b)
			return FALSE;
	}
	return TRUE;
}

/* Which screen edge a HUD element is attached to: -1 left, 1 right, 0 for elements
   that stay centered or that the game places itself. */
static int hud_edge(const char *section, const char *parent)
{
	if (lstrcmpiA(parent, "Speedometer") == 0 || lstrcmpiA(section, "STRING_RACE_TIME_VALUE") == 0 ||
			lstrcmpiA(section, "STRING_CUR_LAP") == 0 || lstrcmpiA(section, "STRING_CUR_POS") == 0)
		return 1;
	if (lstrcmpiA(parent, "Communicator") == 0 || has_prefix(section, "OVL_PORTRAITS_") ||
			has_prefix(section, "PLAYER_"))
		return -1;
	return 0;
}

/* Reads one line of an overlay file: its section name if it starts a section,
   otherwise its key in lower case and where its value starts. */
static void ini_line(const char *line, int size, char *section, char *key, int *value_start)
{
	int end = 0, i, start, length;

	section[0] = key[0] = 0;
	*value_start = 0;

	while (end < size && line[end] != ';')
		end++;

	for (start = 0; start < end && is_space(line[start]); start++)
		;
	if (start < end && line[start] == '[') {
		length = 0;
		for (i = start + 1; i < end && line[i] != ']' && length < 99; i++)
			section[length++] = line[i];
		section[i < end && line[i] == ']' ? length : 0] = 0;
		return;
	}

	for (i = start; i < end && line[i] != '='; i++)
		;
	if (i >= end)
		return;

	length = i;
	while (length > start && is_space(line[length - 1]))
		length--;
	if (length - start < 20) {
		int k;

		for (k = 0; k < length - start; k++) {
			char c = line[start + k];

			key[k] = (c >= 'A' && c <= 'Z') ? (char)(c + 32) : c;
		}
		key[length - start] = 0;
	}

	i++;
	while (i < end && (line[i] == ' ' || line[i] == '\t'))
		i++;
	*value_start = i;
}

/* Adds shift to the number at the start of value, which may have up to three
   decimals. Writes the new number and returns how long the old one was, or 0. */
static int shift_decimal(const char *value, int size, int shift, char *text)
{
	int i = 0, whole = 0, milli, start, unit = 100;
	BOOL negative = size > 0 && value[0] == '-';

	if (negative)
		i++;
	start = i;
	while (i < size && value[i] >= '0' && value[i] <= '9' && whole <= 1000000)
		whole = whole * 10 + (value[i++] - '0');
	if (i == start || whole > 1000000)
		return 0;

	milli = whole * 1000;
	if (i < size && value[i] == '.') {
		i++;
		for (; i < size && value[i] >= '0' && value[i] <= '9'; i++) {
			if (unit == 0)
				return 0;
			milli += (value[i] - '0') * unit;
			unit /= 10;
		}
	}
	if (negative)
		milli = -milli;
	milli += shift * 1000;

	if (milli < 0) {
		*text++ = '-';
		milli = -milli;
	}
	text += wsprintfA(text, "%d", milli / 1000);
	if (milli % 1000 != 0) {
		int fraction = milli % 1000;

		*text++ = '.';
		*text++ = (char)('0' + fraction / 100);
		if (fraction % 100 != 0) {
			*text++ = (char)('0' + fraction / 10 % 10);
			if (fraction % 10 != 0)
				*text++ = (char)('0' + fraction % 10);
		}
	}
	*text = 0;
	return i;
}

static int line_size(const char *data, DWORD left)
{
	DWORD i = 0;

	while (i < left && data[i] != '\n')
		i++;
	return (int)(i < left ? i + 1 : i);
}

/* Fills in the Parent of the section a Position line belongs to: it can come
   before or after that line, so look through the whole section. */
static void section_parent(const char *start, const char *end, char *parent)
{
	static char section[100], key[20];
	const char *line = start;
	int value_start;

	parent[0] = 0;
	while (line < end) {
		int size = line_size(line, (DWORD)(end - line));

		ini_line(line, size, section, key, &value_start);
		if (line != start && section[0] != 0)
			return;
		if (lstrcmpA(key, "parent") == 0) {
			int length = 0;

			while (value_start + length < size && length < 99 && !is_space(line[value_start + length]) &&
					line[value_start + length] != ';') {
				parent[length] = line[value_start + length];
				length++;
			}
			parent[length] = 0;
		}
		line += size;
	}
}

/* Writes an original overlay file with every element that is attached to a screen
   edge moved to that edge for the chosen resolution. The rest stays as it is, so
   the HUD keeps its original size. The result is allocated here. */
static char *transform_overlay(const char *data, DWORD size, int shift, DWORD *result_size)
{
	static char section[100], current[100], key[20], parent[100], number[32];
	const char *line = data;
	const char *end = data + size;
	char *result = HeapAlloc(GetProcessHeap(), 0, size * 2 + 16);
	char *to = result;

	current[0] = parent[0] = 0;
	if (result == NULL)
		return NULL;

	while (line < end) {
		int length = line_size(line, (DWORD)(end - line));
		int value_start, old_size = 0;

		ini_line(line, length, section, key, &value_start);
		if (section[0] != 0) {
			lstrcpyA(current, section);
			section_parent(line, end, parent);
		} else if (lstrcmpA(key, "position") == 0) {
			int edge = hud_edge(current, parent);

			if (edge != 0)
				old_size = shift_decimal(line + value_start, length - value_start, edge * shift, number);
		}

		if (old_size > 0) {
			memcpy(to, line, value_start);
			to += value_start;
			memcpy(to, number, lstrlenA(number));
			to += lstrlenA(number);
			memcpy(to, line + value_start + old_size, length - value_start - old_size);
			to += length - value_start - old_size;
		} else {
			memcpy(to, line, length);
			to += length;
		}
		line += length;
	}

	*result_size = (DWORD)(to - result);
	return result;
}

/* Recognizes the game's own HUD layout. Moving a file that an earlier patcher or
   a hand tuned HUD already changed would give a wrong result. */
static BOOL is_original_overlay(const char *data, DWORD size)
{
	static char section[100], current[100], key[20];
	const char *line = data;
	const char *end = data + size;
	int found = 0;

	current[0] = 0;
	while (line < end) {
		int length = line_size(line, (DWORD)(end - line));
		int value_start;

		ini_line(line, length, section, key, &value_start);
		if (section[0] != 0) {
			lstrcpyA(current, section);
		} else if (lstrcmpA(key, "position") == 0) {
			const char *value = line + value_start;

			if (lstrcmpiA(current, "OVL_SPEEDOMETER_BODY") == 0) {
				if (length - value_start < 4 || !same_bytes(value, "640,", 4))
					return FALSE;
				found++;
			} else if (lstrcmpiA(current, "OVL_COMMUNICATOR_BODY") == 0) {
				if (length - value_start < 2 || !same_bytes(value, "0,", 2))
					return FALSE;
				found++;
			}
		}
		line += length;
	}
	return found == 2;
}

/* Finds the game's own version of an overlay file. The first backup holds it after
   an earlier run, otherwise it is still in the game folder. */
static char *original_overlay(const char *name, DWORD *size)
{
	static char dir[PATH_SIZE], path[PATH_SIZE];
	char *data;
	BOOL has_backup, exists;

	join_path(dir, game_dir, BACKUP_DIR);
	has_backup = find_file(dir, name, path);
	if (has_backup) {
		data = read_file(path, size);
		if (data == NULL) {
			FAIL("could not read %s: %s", path, system_error());
			return NULL;
		}
		if (is_original_overlay(data, *size))
			return data;
		HeapFree(GetProcessHeap(), 0, data);
	}

	exists = find_file(game_dir, name, path);
	if (exists) {
		data = read_file(path, size);
		if (data == NULL) {
			FAIL("could not read %s: %s", path, system_error());
			return NULL;
		}
		if (is_original_overlay(data, *size))
			return data;
		HeapFree(GetProcessHeap(), 0, data);
	}

	if (!has_backup && !exists)
		FAIL("there is no %s in %s", name, game_dir);
	else
		FAIL("no original %s found: it was changed by an older HUD fix. Restore it from the game CD and run the patcher again", name);
	return NULL;
}

/* Writes the HUD overlay files for the chosen resolution, made from the game's own
   files, and moves the files they replace to the backup folder. overlay7.ini comes
   with the "Schaduw" extra car update, which would overwrite it again, so it is
   only written when that update is already installed. */
static BOOL install_overlays(int width, int height)
{
	static char target[PATH_SIZE];
	static char backup_path[PATH_SIZE];
	int shift = hud_shift(width, height);
	unsigned int i;

	for (i = 0; i < sizeof(overlay_names) / sizeof(overlay_names[0]); i++) {
		const char *name = overlay_names[i];
		BOOL exists = find_file(game_dir, name, target);
		char *original, *data;
		DWORD original_size, size;

		if (!exists && lstrcmpA(name, EXTRA_CAR_OVERLAY) == 0) {
			SAY("Skipped %s: the \"Schaduw\" extra car update is not installed.\r\n", name);
			say("  Install that update first, then run the patcher again.\r\n");
			continue;
		}

		original = original_overlay(name, &original_size);
		if (original == NULL)
			return FALSE;
		data = transform_overlay(original, original_size, shift, &size);
		HeapFree(GetProcessHeap(), 0, original);
		if (data == NULL)
			return FAIL("not enough memory for %s", name);

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
				HeapFree(GetProcessHeap(), 0, data);
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

		HeapFree(GetProcessHeap(), 0, data);
		SAY("Installed %s\r\n", name);
	}

	return TRUE;
}

/* Refuses to continue without administrator rights, which are needed to write into
   C:\Program Files. The manifest makes Windows Vista and newer ask for them; this
   catches the cases where that request is bypassed, and Windows XP, which ignores
   it. It checks for an enabled Administrators group: tokens that only carry it as
   "deny only" cannot write there. Windows 9x has no such rights, and on systems
   without these functions a write that fails is still reported. */
static BOOL check_admin(void)
{
	typedef BOOL (WINAPI *allocate_sid_fn)(PSID_IDENTIFIER_AUTHORITY, BYTE, DWORD, DWORD,
		DWORD, DWORD, DWORD, DWORD, DWORD, DWORD, PSID *);
	typedef BOOL (WINAPI *check_membership_fn)(HANDLE, PSID, PBOOL);
	typedef PVOID (WINAPI *free_sid_fn)(PSID);

	static char path[MAX_PATH + 32];
	static SID_IDENTIFIER_AUTHORITY nt_authority = {SECURITY_NT_AUTHORITY};
	allocate_sid_fn allocate_sid;
	check_membership_fn check_membership;
	free_sid_fn free_sid;
	HMODULE advapi;
	PSID administrators;
	BOOL member = FALSE;
	BOOL checked;
	UINT size;

	if (GetVersion() & 0x80000000)
		return TRUE;

	/* From the system folder only, because this runs with administrator rights
	   and a stray DLL next to the patcher must not be loaded. */
	size = GetSystemDirectoryA(path, MAX_PATH);
	if (size == 0 || size >= MAX_PATH)
		return TRUE;
	lstrcatA(path, "\\advapi32.dll");
	advapi = LoadLibraryA(path);
	if (advapi == NULL)
		return TRUE;

	allocate_sid = (allocate_sid_fn)GetProcAddress(advapi, "AllocateAndInitializeSid");
	check_membership = (check_membership_fn)GetProcAddress(advapi, "CheckTokenMembership");
	free_sid = (free_sid_fn)GetProcAddress(advapi, "FreeSid");
	if (allocate_sid == NULL || check_membership == NULL || free_sid == NULL)
		return TRUE;

	if (!allocate_sid(&nt_authority, 2, SECURITY_BUILTIN_DOMAIN_RID, DOMAIN_ALIAS_RID_ADMINS,
			0, 0, 0, 0, 0, 0, &administrators))
		return FAIL("%s", system_error());

	checked = check_membership(NULL, administrators, &member);
	if (!checked) {
		FAIL("%s", system_error());
		free_sid(administrators);
		return FALSE;
	}
	free_sid(administrators);

	if (!member)
		return FAIL("the patcher needs administrator rights to write the game files. Right-click it and choose \"Run as administrator\" (\"Run as...\" on Windows XP)");

	return TRUE;
}

/* Reports whether the patcher is alone in its console, as when it is started from
   Explorer: that window closes as soon as the patcher exits. Windows 9x cannot tell,
   so it counts as alone there. */
static BOOL console_will_close(void)
{
	typedef DWORD (WINAPI *process_list_fn)(LPDWORD, DWORD);

	process_list_fn process_list = (process_list_fn)GetProcAddress(
		GetModuleHandleA("kernel32.dll"), "GetConsoleProcessList");
	DWORD ids[2];

	return process_list == NULL || process_list(ids, 2) == 1;
}

/* Does the actual work. Every failure is reported, together with what it means
   for the game files, so the patcher never fails silently. */
static BOOL run(void)
{
	int width, height;

	say("A2 Racer 4 Fixes v" PATCHER_VERSION "\r\n");
	say("--------------------------------\r\n\r\n");

	if (!check_admin()) {
		SAY("Error: %s\r\n", error);
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

	if (!install_overlays(width, height)) {
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

	/* Keep the result readable when the console closes with the patcher. */
	if (GetFileType(input) == FILE_TYPE_CHAR && console_will_close()) {
		say("\r\nPress Enter to close.");
		read_line(line, sizeof(line));
	}

	ExitProcess(ok ? 0 : 1);
}
