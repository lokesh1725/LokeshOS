#include <stdio.h>
#include <string.h>

#define MAX_ATTEMPTS 3
#define PIN_LENGTH 4

int main(void)
{
    char pin[64];
    int attempts = 0;

    printf("==================================\n");
    printf("       LokeshOS Authentication\n");
    printf("==================================\n");

    while (attempts < MAX_ATTEMPTS) {
        printf("Enter LokeshOS PIN: ");
        fflush(stdout);

        if (fgets(pin, sizeof(pin), stdin) == NULL)
            return 1;

        pin[strcspn(pin, "\n")] = '\0';

        /*
         * Development PIN.
         * We will replace this with secure hash verification.
         */
        if (strcmp(pin, "1234") == 0) {
            printf("Authentication successful.\n");
            return 0;
        }

        attempts++;

        printf("Authentication failed.\n");

        if (attempts < MAX_ATTEMPTS)
            printf("Attempts remaining: %d\n",
                   MAX_ATTEMPTS - attempts);
    }

    printf("Too many failed attempts. Access locked.\n");
    return 1;
}