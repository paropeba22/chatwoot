#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { pathToFileURL } from 'node:url';

export const TARGET_NODES = [
  'TI_API_Contract_V1',
  'TI_Precheck_Adapter_V1',
  'TI_Match_Adapter_V1',
  'TI_Commit_Adapter_V1',
  'TI_Feedback_Adapter_V1',
];

const EXPECTED = {
  paths: [
    '/api/v1/technical_incident_checks/precheck',
    '/api/v1/technical_incident_checks/:id/match',
    '/api/v1/technical_incident_checks/:id/commit',
    '/api/v1/technical_incident_evaluations/:id/feedback',
  ],
  methods: ['POST'],
  versions: ['1.0'],
  headers: ['api_access_token', 'Content-Type'],
  aliases: ['id', 'check_id', 'evaluation_id', 'commit_token'],
  precheckFields: [
    'conversation_display_id',
    'source_message_id',
    'mode',
    'request_id',
    'contract_version',
    'classification',
  ],
  classificationFields: [
    'is_support_issue',
    'problem_type',
    'service_key',
    'symptoms',
    'semantic_confidence',
    'topic_change',
    'needs_clarification',
    'reason_code',
  ],
  matchFields: [
    'contracts',
    'sanitized_contracts',
    'selected_contract_id',
    'selected_contract',
  ],
  contractFields: [
    'contract_id',
    'status',
    'pop_id',
    'pop_name',
    'service_group',
    'connection_type',
    'state',
    'city',
    'neighborhood',
    'postal_code',
    'street',
    'number',
    'location',
  ],
  feedbackFields: ['feedback', 'note'],
  statuses: [
    'no_candidate',
    'general_match',
    'localized_candidate',
    'needs_document',
    'needs_contract_selection',
    'matched',
    'ambiguous',
    'expired',
    'fallback',
    'duplicate',
    'accepted',
    'stale',
  ],
  behavior: ['timeout', 'retry', 'duplicate', 'stale', 'ambiguous', 'fallback'],
};

const SENSITIVE_KEY =
  /(?:credential|password|secret|authorization|api[_-]?key|access[_-]?token|bearer)/i;
const LITERAL_SECRET =
  /((?:api[_-]?access[_-]?token|authorization|api[_-]?key|password|secret)\s*[:=]\s*)(['"`])([^'"`\r\n]+)\2/gi;

function workflowFromExport(parsed) {
  const candidates = [
    parsed,
    parsed?.workflow,
    parsed?.data,
    parsed?.data?.workflow,
    ...(Array.isArray(parsed) ? parsed : []),
  ];
  return candidates.find(candidate => Array.isArray(candidate?.nodes));
}

function redactString(value) {
  return value
    .replace(/Bearer\s+[A-Za-z0-9._~+/=-]{8,}/gi, 'Bearer [REDACTED]')
    .replace(LITERAL_SECRET, '$1$2[REDACTED]$2')
    .replace(
      /([?&](?:token|secret|api[_-]?key|access[_-]?token)=)[^&\s]+/gi,
      '$1[REDACTED]'
    );
}

function sanitize(value, key = '') {
  if (SENSITIVE_KEY.test(key)) {
    if (key === 'credentials' && value && typeof value === 'object') {
      return Object.fromEntries(
        Object.keys(value).map(name => [name, '[REDACTED]'])
      );
    }
    return '[REDACTED]';
  }
  if (Array.isArray(value)) return value.map(item => sanitize(item));
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([childKey, childValue]) => [
        childKey,
        sanitize(childValue, childKey),
      ])
    );
  }
  return typeof value === 'string' ? redactString(value) : value;
}

function collectText(value, output = []) {
  if (typeof value === 'string') output.push(value);
  if (Array.isArray(value)) value.forEach(item => collectText(item, output));
  if (value && typeof value === 'object') {
    Object.entries(value).forEach(([key, child]) => {
      output.push(key);
      collectText(child, output);
    });
  }
  return output;
}

function containsToken(text, token) {
  if (token.includes(':id')) {
    const pattern = token
      .replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
      .replace(':id', '[^/"\'`]+');
    return new RegExp(pattern).test(text);
  }
  return text.toLowerCase().includes(token.toLowerCase());
}

function comparisonRows(text) {
  return Object.entries(EXPECTED).flatMap(([area, values]) =>
    values.map(value => ({
      area,
      value,
      observed: containsToken(text, value),
    }))
  );
}

function markdownReport({ workflow, nodes, rows }) {
  const metadata = {
    workflow_id: workflow.id ?? workflow.workflowId ?? 'not_exposed',
    version_id: workflow.versionId ?? workflow.version_id ?? 'not_exposed',
    name: workflow.name ?? 'not_exposed',
  };
  const lines = [
    '# AntiGravity V1 redacted contract comparison',
    '',
    '> Generated locally from a workflow JSON export. No credential values are retained.',
    '',
    `- workflow: \`${metadata.workflow_id}\``,
    `- version: \`${metadata.version_id}\``,
    `- name: \`${metadata.name}\``,
    '',
    '## Code node hashes',
    '',
    '| Node | SHA-256 of original parameters |',
    '| --- | --- |',
    ...nodes.map(node => `| ${node.name} | \`${node.parameters_sha256}\` |`),
    '',
    '## Field-by-field lexical comparison',
    '',
    '| Area | Expected token | Observed in the five nodes |',
    '| --- | --- | --- |',
    ...rows.map(
      row =>
        `| ${row.area} | \`${row.value.replaceAll('|', '\\|')}\` | ${
          row.observed ? 'yes' : 'NO'
        } |`
    ),
    '',
    '## Mandatory manual decisions',
    '',
    '- Confirm whether any internal `no_match` is normalized to Chatwoot `no_candidate`.',
    '- Confirm HTTP method, timeout, retry count/backoff and retryable status codes in each adapter.',
    '- Confirm required versus optional payload fields and the selected opaque-ID alias.',
    '- Confirm unknown response fields and every fallback/reason-code branch.',
    '- A lexical `yes` proves presence only; it does not prove runtime behavior.',
    '',
  ];
  return lines.join('\n');
}

export async function extractContract(inputFile, outputDirectory) {
  const parsed = JSON.parse(await fs.readFile(inputFile, 'utf8'));
  const workflow = workflowFromExport(parsed);
  if (!workflow)
    throw new Error('The JSON does not contain a workflow nodes array');

  const selected = TARGET_NODES.map(name =>
    workflow.nodes.find(node => node.name === name)
  );
  const missing = TARGET_NODES.filter((_, index) => !selected[index]);
  if (missing.length)
    throw new Error(`Missing required nodes: ${missing.join(', ')}`);

  const nodes = selected.map(node => ({
    id: node.id,
    name: node.name,
    type: node.type,
    typeVersion: node.typeVersion,
    disabled: node.disabled === true,
    parameters_sha256: crypto
      .createHash('sha256')
      .update(JSON.stringify(node.parameters ?? {}))
      .digest('hex'),
    parameters: sanitize(node.parameters ?? {}),
    credentials: sanitize(node.credentials ?? {}, 'credentials'),
  }));
  const text = collectText(nodes).join('\n');
  const rows = comparisonRows(text);
  const redacted = {
    workflow: {
      id: workflow.id,
      name: workflow.name,
      versionId: workflow.versionId,
    },
    extracted_at: new Date().toISOString(),
    nodes,
  };

  await fs.mkdir(outputDirectory, { recursive: true });
  const jsonPath = path.join(
    outputDirectory,
    'antigravity-contract-redacted.json'
  );
  const reportPath = path.join(
    outputDirectory,
    'antigravity-contract-comparison.md'
  );
  await fs.writeFile(jsonPath, `${JSON.stringify(redacted, null, 2)}\n`);
  await fs.writeFile(reportPath, markdownReport({ workflow, nodes, rows }));

  return {
    jsonPath,
    reportPath,
    missingTokens: rows.filter(row => !row.observed),
  };
}

async function main() {
  const [, , inputFile, outputDirectory = 'tmp/technical-incidents-contract'] =
    process.argv;
  if (!inputFile) {
    throw new Error(
      'Usage: node script/technical_incidents/extract_antigravity_contract.mjs <workflow-export.json> [output-directory]'
    );
  }
  const result = await extractContract(
    path.resolve(inputFile),
    path.resolve(outputDirectory)
  );
  process.stdout.write(
    `${JSON.stringify(
      {
        redacted_json: result.jsonPath,
        comparison: result.reportPath,
        missing_tokens: result.missingTokens.length,
      },
      null,
      2
    )}\n`
  );
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  main().catch(error => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
