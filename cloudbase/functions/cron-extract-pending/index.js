const RETRYABLE_STATUS = new Set([502, 503, 504]);
const ATTEMPTS = 3;
const ATTEMPT_TIMEOUT_MS = 20000;

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

async function callCronTarget(url, secret) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), ATTEMPT_TIMEOUT_MS);
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${secret}`,
      },
      signal: controller.signal,
    });
    const body = await response.text();
    return { status: response.status, ok: response.ok, body };
  } finally {
    clearTimeout(timeout);
  }
}

exports.main = async () => {
  const url = process.env.CRON_TARGET_URL;
  const secret = process.env.CRON_SECRET;

  if (!url || !secret) {
    throw new Error("CRON_TARGET_URL and CRON_SECRET must be configured");
  }

  let lastError;
  let lastResult;
  for (let attempt = 1; attempt <= ATTEMPTS; attempt += 1) {
    try {
      const result = await callCronTarget(url, secret);
      lastResult = result;
      if (result.ok) {
        return {
          status: result.status,
          body: result.body,
          attempt,
        };
      }
      if (!RETRYABLE_STATUS.has(result.status) || attempt === ATTEMPTS) {
        throw new Error(`Cron target returned ${result.status}: ${result.body}`);
      }
    } catch (error) {
      lastError = error;
      if (attempt === ATTEMPTS) {
        throw error;
      }
    }

    await sleep(1000 * attempt);
  }

  if (lastResult) {
    throw new Error(`Cron target returned ${lastResult.status}: ${lastResult.body}`);
  }
  throw lastError;
};
